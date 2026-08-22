/// Which tags start a release of this repository, READ from the workflow that decides it.
///
/// THE GRAMMAR IS NOT WRITTEN IN THIS FILE. .github/workflows/release.yml triggers on `on.push.tags`
/// and on nothing else, so a tag its filter does not match starts nothing at all — no gate, no
/// GitHub Release, and no ref for a consumer to name. The patterns are read out of that file every
/// time tool/release.dart runs, and what a person types is held against them. A grammar spelled a
/// second time in Dart would be a second answer to "may this be released", and the day the
/// workflow's filter was widened or narrowed the two would disagree with nothing in this repository
/// able to notice.
///
/// WHAT THE PATTERN LANGUAGE IS, and why it is not a regular expression. GitHub's filter pattern:
/// `*` matches a run of characters but no `/`, `**` matches one including `/`, `+` matches one or
/// more of what stands before it, `?` matches zero or one of it, `[...]` matches one character of
/// the set, `\` takes the next character literally, and a leading `!` negates the whole pattern.
/// Everything else — `.` and `-` included, which is why `[0-9]+.[0-9]+.[0-9]+-*` reads a literal dot
/// and a literal hyphen — stands for itself. A pattern is matched against the WHOLE tag, so one that
/// ends after its last atom refuses everything standing behind it.
///
/// A PATTERN THIS CANNOT READ IS REFUSED BY NAME, never guessed at. A `!`, a `[` that never closes
/// and a quantifier with nothing in front of it each end the program with the pattern quoted,
/// because a filter read wrongly would refuse a version the workflow accepts or accept one it
/// ignores, and both are worse than being told the file cannot be read.
library;

/// The workflow whose `on.push.tags` decides which tags start a release, as this repository holds
/// it.
///
/// It is stated relative to the REPOSITORY and not to this package: the release is the whole
/// repository's, so the file that decides it stands above the package this program lives in.
const String releaseWorkflowPath = '.github/workflows/release.yml';

/// One thing a filter pattern reads at one place in a tag name.
final class PatternAtom {
  /// [source] is the pattern text this was read from, [expression] what it matches.
  const PatternAtom({required this.source, required this.expression});

  /// The pattern text this was read from, spelled as the workflow spells it.
  final String source;

  /// What it matches, as a regular expression this program can run.
  final String expression;
}

/// One pattern of `on.push.tags`, read into what it matches.
final class TagPattern {
  TagPattern._({required this.source, required this.atoms, required this.unreadable})
    : _whole = unreadable == null
          ? RegExp('^${atoms.map((PatternAtom each) => each.expression).join()}\$')
          : null;

  /// [source] read as a GitHub filter pattern, or a pattern saying why it could not be.
  factory TagPattern.read(String source) {
    if (source.isEmpty) {
      return TagPattern._unreadable(source, 'it is empty, and an empty filter matches no tag');
    }
    final List<PatternAtom> atoms = <PatternAtom>[];
    int index = 0;
    while (index < source.length) {
      final String character = source[index];
      final PatternAtom atom;
      switch (character) {
        case '!' when atoms.isEmpty:
          return TagPattern._unreadable(
            source,
            'it begins with "!", which negates the whole pattern — this program reads what a filter '
            'accepts and cannot read what one refuses',
          );
        case '*':
          final bool crossesSlashes = index + 1 < source.length && source[index + 1] == '*';
          atom = PatternAtom(
            source: crossesSlashes ? '**' : '*',
            expression: crossesSlashes ? '.*' : '[^/]*',
          );
          index += crossesSlashes ? 2 : 1;
        case '[':
          final int close = source.indexOf(']', index + 1);
          if (close < 0) {
            return TagPattern._unreadable(
              source,
              'it carries a "[" at character ${index + 1} that never closes',
            );
          }
          final String set = source.substring(index, close + 1);
          atom = PatternAtom(source: set, expression: set);
          index = close + 1;
        case r'\':
          if (index + 1 >= source.length) {
            return TagPattern._unreadable(
              source,
              'it ends on a backslash, which takes the next character literally and there is none',
            );
          }
          final String literal = source[index + 1];
          atom = PatternAtom(source: '\\$literal', expression: RegExp.escape(literal));
          index += 2;
        case '+' || '?':
          return TagPattern._unreadable(
            source,
            'it carries "$character" at character ${index + 1} with nothing in front of it, and '
            '"$character" says how often the thing before it may stand there',
          );
        default:
          atom = PatternAtom(source: character, expression: RegExp.escape(character));
          index += 1;
      }
      if (index < source.length && (source[index] == '+' || source[index] == '?')) {
        atoms.add(
          PatternAtom(
            source: '${atom.source}${source[index]}',
            expression: '(?:${atom.expression})${source[index]}',
          ),
        );
        index += 1;
      } else {
        atoms.add(atom);
      }
    }
    try {
      return TagPattern._(source: source, atoms: atoms, unreadable: null);
    } on FormatException catch (broken) {
      return TagPattern._unreadable(source, 'what it reads is no expression: ${broken.message}');
    }
  }

  factory TagPattern._unreadable(String source, String why) =>
      TagPattern._(source: source, atoms: const <PatternAtom>[], unreadable: why);

  /// The pattern as the workflow spells it.
  final String source;

  /// What it reads, in the order it reads it, and empty when it could not be read.
  final List<PatternAtom> atoms;

  /// Why this pattern could not be read, or null when it was.
  final String? unreadable;

  final RegExp? _whole;

  /// Whether a tag named [tag] would start the workflow.
  bool accepts(String tag) => _whole?.hasMatch(tag) ?? false;

  /// Where [tag] stops being what this pattern reads, or null when it does not stop.
  ///
  /// The place is found by matching the pattern's atoms one more at a time: the longest run of them
  /// that still reads a beginning of [tag] says which atom is the one with nothing to read, and how
  /// far into [tag] it stood. That is what puts the person's own characters in the refusal instead
  /// of the whole pattern a second time.
  String? whereItStops(String tag) {
    if (accepts(tag)) {
      return null;
    }
    int read = 0;
    int reached = 0;
    for (int count = 1; count <= atoms.length; count++) {
      final RegExpMatch? match = RegExp(
        '^${atoms.take(count).map((PatternAtom each) => each.expression).join()}',
      ).firstMatch(tag);
      if (match == null) {
        break;
      }
      read = count;
      reached = match.end;
    }
    final String left = tag.substring(reached);
    if (read == atoms.length) {
      return 'the filter has read all of "${tag.substring(0, reached)}" and "$left" is left over';
    }
    final String next = atoms[read].source;
    final String so = reached == 0 ? 'first' : 'after "${tag.substring(0, reached)}"';
    return left.isEmpty
        ? 'the filter reads $next $so, and "$tag" ends there'
        : 'the filter reads $next $so, and "$left" stands there';
  }
}

/// Every pattern `on.push.tags` states, and the one question asked of them.
final class TagFilter {
  /// The filter these [patterns] are, in the order the workflow lists them.
  const TagFilter({required this.patterns});

  /// The filter stated by [workflow], the text of [releaseWorkflowPath].
  factory TagFilter.ofWorkflow(String workflow) => TagFilter(
    patterns: <TagPattern>[
      for (final String pattern in tagPatternsIn(workflow)) TagPattern.read(pattern),
    ],
  );

  /// What the workflow triggers on, in the order it lists them.
  final List<TagPattern> patterns;

  /// Why this filter cannot be used to decide anything, or null when it can.
  String? get unreadable {
    if (patterns.isEmpty) {
      return '$releaseWorkflowPath states no tag under on.push.tags, so nothing here can say which '
          'tag starts a release — and a version answered without that is a version nobody checked';
    }
    for (final TagPattern pattern in patterns) {
      if (pattern.unreadable case final String why) {
        return '$releaseWorkflowPath triggers on "${pattern.source}", which this program cannot '
            'read: $why';
      }
    }
    return null;
  }

  /// Every pattern as the workflow spells it, for a screen to show.
  List<String> get stated => patterns.map((TagPattern each) => each.source).toList(growable: false);

  /// Whether a tag named [tag] would start the workflow.
  bool accepts(String tag) => patterns.any((TagPattern each) => each.accepts(tag));

  /// Why [tag] would start nothing, or null when it would.
  ///
  /// The refusal names the file the filter was read from, so whoever reads it can go and see the
  /// line that refused them rather than take this program's word for what the grammar is.
  String? refusalFor(String tag) {
    if (unreadable case final String why) {
      return why;
    }
    if (accepts(tag)) {
      return null;
    }
    final String stops = patterns
        .map((TagPattern each) => '${each.source} — ${each.whereItStops(tag)}')
        .join('; ');
    return '"$tag" would start no release: $releaseWorkflowPath triggers on tags matching '
        '${patterns.length == 1 ? 'this pattern' : 'one of these patterns'}, and $stops';
  }
}

/// The patterns `on.push.tags` states in [workflow], in the order they are listed.
///
/// READ AS LINES rather than as YAML, because everything under tool/ imports nothing but `dart:` —
/// the job that writes the release notes runs one of these programs with the SDK alone and no
/// `dart pub get` in front of it. What is walked is three keys and a list of items under them, and a
/// file that does not carry them answers with nothing, which [TagFilter.unreadable] turns into a
/// refusal rather than into a filter that accepts everything.
List<String> tagPatternsIn(String workflow) {
  const List<String> path = <String>['on', 'push', 'tags'];
  int depth = 0;
  int enclosing = -1;
  final List<String> patterns = <String>[];
  for (final String line in workflow.split('\n')) {
    final String content = line.trimLeft();
    if (content.isEmpty || content.startsWith('#')) {
      continue;
    }
    final int indent = line.length - content.length;
    if (depth == path.length) {
      if (indent <= enclosing) {
        break;
      }
      if (content.startsWith('- ')) {
        patterns.add(_unquoted(content.substring(2).trim()));
      }
      continue;
    }
    if (indent <= enclosing) {
      return const <String>[];
    }
    if (_keyOf(content) == path[depth]) {
      depth += 1;
      enclosing = indent;
    }
  }
  return patterns;
}

/// The key [content] states before its colon, or null when it states none.
String? _keyOf(String content) {
  final int colon = content.indexOf(':');
  return colon < 0 ? null : _unquoted(content.substring(0, colon).trim());
}

/// [text] without the quotes YAML lets a value carry.
String _unquoted(String text) {
  for (final String quote in <String>["'", '"']) {
    if (text.length >= 2 && text.startsWith(quote) && text.endsWith(quote)) {
      return text.substring(1, text.length - 1);
    }
  }
  return text;
}
