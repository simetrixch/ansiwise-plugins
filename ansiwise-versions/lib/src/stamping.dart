/// Surgical stamping: one value token changes, everything else stays byte for byte.
///
/// The files a pin lives in are comment-heavy YAML and container build files, and the comments
/// are the documentation. A rewrite through a parser and printer reflows them, so nothing here
/// parses a document: the file is lines, the site is found by anchors and keys, and the edit
/// replaces the value token on exactly one line.
///
/// **Every site must be FOUND, and found ONCE.** A chart stamper that matches with a pattern doing
/// nothing when the dependency is absent prints success while the pin goes nowhere. Here a site
/// that matches no line, or more than one, is a refusal
/// naming the file and what was looked for, so a declaration that drifted from its tree stops the
/// stamp instead of thinning it.
///
/// **Line endings survive.** These trees are edited on Windows too, and a working copy may carry
/// CRLF. Each line's carriage return is kept apart from its body and put back on the way out, so
/// stamping a file never rewrites lines the stamp had nothing to say about — rewriting them leaves
/// a repository dirty after every run and invites an accidental commit.
library;

import 'declaration.dart';

/// What holding one stamp against one file's content found.
sealed class StampOutcome {
  const StampOutcome();
}

/// The site was found and already carries the pin.
final class StampStands extends StampOutcome {
  /// Records that [at] already carries the value.
  const StampStands({required this.at});

  /// The line that carries it, trimmed.
  final String at;
}

/// The site was found and carries something else; [content] is the file with the pin written.
final class StampReady extends StampOutcome {
  /// Records the rewrite.
  const StampReady({required this.content, required this.was, required this.becomes});

  /// The whole file after the edit.
  final String content;

  /// The line as it stands, trimmed.
  final String was;

  /// The line as it will stand, trimmed.
  final String becomes;
}

/// The site could not be found, or could mean more than one place.
final class StampRefused extends StampOutcome {
  /// Refuses the stamp for [reason].
  const StampRefused(this.reason);

  /// What was looked for and what was found instead.
  final String reason;
}

/// Holds [stamp] against [content] and answers what writing [value] there means.
StampOutcome stampInto(String content, PinStamp stamp, String value) {
  final List<_Line> lines = _lines(content);
  return switch (stamp) {
    final YamlValueStamp site => _stampYamlValue(lines, site, value),
    final ChartDependencyStamp site => _stampKeyUnderAnchor(
      lines,
      anchor: '- name: ${site.dependency}',
      anchorSays: 'the dependency "${site.dependency}"',
      key: 'version',
      value: value,
    ),
    final ListPinStamp site => _stampListEntry(lines, site, value),
    final DockerfileFromStamp site => _stampFrom(lines, site, value),
    final DockerfileArgStamp site => _stampArg(lines, site, value),
  };
}

/// The `repository:` of [dependency] in the Chart.yaml [content], or null with the reason why not.
///
/// This is the report's half of the coupling the [ChartDependencyStamp] kind exists for: the
/// repository to ask about a dependency is the one the stamped Chart.yaml itself names, read out
/// of the same block the stamp writes.
({String? repository, String? whyNot}) chartDependencyRepository(
  String content,
  String dependency,
) {
  final List<_Line> lines = _lines(content);
  final _Block? block = _blockUnder(lines, '- name: $dependency');
  if (block == null) {
    return (repository: null, whyNot: 'declares the dependency "$dependency" not exactly once');
  }
  for (int i = block.first; i < block.past; i++) {
    final RegExpMatch? match = _valueLine('repository').firstMatch(lines[i].body);
    if (match != null && _contentIndent(lines[i].body) == block.indent) {
      return (repository: match[3], whyNot: null);
    }
  }
  return (repository: null, whyNot: 'declares no repository for "$dependency"');
}

StampOutcome _stampYamlValue(List<_Line> lines, YamlValueStamp site, String value) {
  final int first;
  final int past;
  final int indent;
  final String? anchor = site.anchor;
  if (anchor == null) {
    first = 0;
    past = lines.length;
    indent = 0;
  } else {
    final _Block? block = _blockUnder(lines, anchor);
    if (block == null) {
      return StampRefused('holds the anchor "$anchor" not exactly once');
    }
    first = block.first;
    past = block.past;
    indent = block.indent;
  }
  final List<int> found = <int>[];
  for (int i = first; i < past; i++) {
    final String body = lines[i].body;
    if (_isBlankOrComment(body) || _isListItem(body)) {
      continue;
    }
    if (_contentIndent(body) == indent && _valueLine(site.key).hasMatch(body)) {
      found.add(i);
    }
  }
  final String where = anchor == null ? 'at the top level' : 'under "$anchor"';
  if (found.length != 1) {
    return StampRefused(
      found.isEmpty
          ? 'holds no value of "${site.key}" $where'
          : 'holds ${found.length} values of "${site.key}" $where, and a stamp writes exactly one',
    );
  }
  return _replaceValue(lines, found.single, site.key, value);
}

StampOutcome _stampKeyUnderAnchor(
  List<_Line> lines, {
  required String anchor,
  required String anchorSays,
  required String key,
  required String value,
}) {
  final _Block? block = _blockUnder(lines, anchor);
  if (block == null) {
    return StampRefused('declares $anchorSays not exactly once');
  }
  final List<int> found = <int>[];
  for (int i = block.first; i < block.past; i++) {
    final String body = lines[i].body;
    if (_isBlankOrComment(body) || _isListItem(body)) {
      continue;
    }
    if (_contentIndent(body) == block.indent && _valueLine(key).hasMatch(body)) {
      found.add(i);
    }
  }
  if (found.length != 1) {
    return StampRefused(
      found.isEmpty
          ? 'holds no "$key" for $anchorSays'
          : 'holds ${found.length} values of "$key" for $anchorSays',
    );
  }
  return _replaceValue(lines, found.single, key, value);
}

StampOutcome _stampListEntry(List<_Line> lines, ListPinStamp site, String value) {
  final _Block? block = _blockUnder(lines, site.anchor, siblings: false);
  if (block == null) {
    return StampRefused('holds the anchor "${site.anchor}" not exactly once');
  }
  final RegExp entryLine = RegExp('^(\\s*-\\s+${RegExp.escape(site.entry)}=)(\\S+)(\\s*)\$');
  final List<int> found = <int>[];
  for (int i = block.first; i < block.past; i++) {
    if (entryLine.hasMatch(lines[i].body)) {
      found.add(i);
    }
  }
  if (found.length != 1) {
    return StampRefused(
      found.isEmpty
          ? 'lists no entry "${site.entry}=" under "${site.anchor}"'
          : 'lists "${site.entry}=" ${found.length} times under "${site.anchor}"',
    );
  }
  final int at = found.single;
  final RegExpMatch match = entryLine.firstMatch(lines[at].body)!;
  if (match[2] == value) {
    return StampStands(at: lines[at].body.trim());
  }
  final String was = lines[at].body;
  lines[at] = lines[at].withBody('${match[1]}$value${match[3]}');
  return StampReady(content: _joined(lines), was: was.trim(), becomes: lines[at].body.trim());
}

StampOutcome _stampFrom(List<_Line> lines, DockerfileFromStamp site, String value) {
  final RegExp fromLine = RegExp(r'^(FROM\s+)(\S+)(.*)$');
  final List<int> found = <int>[];
  for (int i = 0; i < lines.length; i++) {
    final RegExpMatch? match = fromLine.firstMatch(lines[i].body);
    if (match != null && match[2]!.contains('${site.image}:')) {
      found.add(i);
    }
  }
  if (found.length != 1) {
    return StampRefused(
      found.isEmpty
          ? 'has no FROM line naming "${site.image}"'
          : 'has ${found.length} FROM lines naming "${site.image}"',
    );
  }
  final int at = found.single;
  final RegExpMatch match = fromLine.firstMatch(lines[at].body)!;
  final String token = match[2]!;
  final int colon = token.indexOf(':');
  final String reference = token.substring(colon + 1);
  if (reference == value) {
    return StampStands(at: lines[at].body.trim());
  }
  final String was = lines[at].body;
  lines[at] = lines[at].withBody('${match[1]}${token.substring(0, colon)}:$value${match[3]}');
  return StampReady(content: _joined(lines), was: was.trim(), becomes: lines[at].body.trim());
}

StampOutcome _stampArg(List<_Line> lines, DockerfileArgStamp site, String value) {
  final RegExp argLine = RegExp('^(ARG\\s+${RegExp.escape(site.argument)}=)(\\S+)(\\s*)\$');
  final List<int> found = <int>[];
  for (int i = 0; i < lines.length; i++) {
    if (argLine.hasMatch(lines[i].body)) {
      found.add(i);
    }
  }
  if (found.length != 1) {
    return StampRefused(
      found.isEmpty
          ? 'states no ARG "${site.argument}"'
          : 'states ARG "${site.argument}" ${found.length} times',
    );
  }
  final int at = found.single;
  final RegExpMatch match = argLine.firstMatch(lines[at].body)!;
  if (match[2] == value) {
    return StampStands(at: lines[at].body.trim());
  }
  final String was = lines[at].body;
  lines[at] = lines[at].withBody('${match[1]}$value${match[3]}');
  return StampReady(content: _joined(lines), was: was.trim(), becomes: lines[at].body.trim());
}

StampOutcome _replaceValue(List<_Line> lines, int at, String key, String value) {
  final RegExpMatch match = _valueLine(key).firstMatch(lines[at].body)!;
  if (match[3] == value) {
    return StampStands(at: lines[at].body.trim());
  }
  final String was = lines[at].body;
  lines[at] = lines[at].withBody('${match[1]}${match[2]}$value${match[2]}${match[4]}');
  return StampReady(content: _joined(lines), was: was.trim(), becomes: lines[at].body.trim());
}

/// A `key: value` line: indentation, an optional list dash, the key, one value token that carries
/// no whitespace, its quoting kept as found, and whatever comment follows.
///
/// Group 1 is everything through the space after the colon, 2 the quote (possibly empty), 3 the
/// value, 4 the trailing whitespace and comment. A version never carries whitespace or a quote,
/// so the token pattern is exact rather than permissive — a line this cannot read is a line this
/// must not rewrite.
RegExp _valueLine(String key) =>
    RegExp('^(\\s*(?:-\\s+)?${RegExp.escape(key)}:\\s*)(["\']?)([^\\s"\']+)\\2(\\s*(?:#.*)?)\$');

/// The lines from an anchor to the end of the block it opens.
///
/// Two shapes, told apart by the caller, because an anchor is read in two different roles. A key
/// found by a SIBLING anchor — the `channel:` beside a `snap:`, the `version:` beside a
/// `- name:` — lives at the anchor's own column, so the block runs until something stands further
/// left or a new list item begins at or left of the anchor. An anchor that opens a LIST owns only
/// what stands deeper than itself, so there the block ends at the first line back at the anchor's
/// column — which is the next key of the same map, exactly what must not be searched. Blank lines
/// and comments neither match nor end anything: the files this reads keep their documentation
/// between the lines it is about.
final class _Block {
  const _Block({required this.first, required this.past, required this.indent});

  /// The first line after the anchor.
  final int first;

  /// One past the last line of the block.
  final int past;

  /// The content column of the anchor, which is where sibling keys stand.
  final int indent;
}

_Block? _blockUnder(List<_Line> lines, String anchor, {bool siblings = true}) {
  final List<int> found = <int>[];
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].body.trim() == anchor) {
      found.add(i);
    }
  }
  if (found.length != 1) {
    return null;
  }
  final int at = found.single;
  final int indent = _contentIndent(lines[at].body);
  int past = at + 1;
  while (past < lines.length) {
    final String body = lines[past].body;
    if (!_isBlankOrComment(body)) {
      final int column = _contentIndent(body);
      final bool ends = siblings
          ? column < indent || (_isListItem(body) && column <= indent)
          : column <= indent;
      if (ends) {
        break;
      }
    }
    past++;
  }
  return _Block(first: at + 1, past: past, indent: indent);
}

/// The column the line's content starts at, where a list dash belongs to the indentation.
///
/// `  - name: x` answers 4: the dash marks the item, and the item's keys stand where `name`
/// stands — which is what makes an item's siblings and its own keys tell apart by one number.
int _contentIndent(String body) {
  int column = 0;
  while (column < body.length && body[column] == ' ') {
    column++;
  }
  if (column < body.length && body[column] == '-') {
    int after = column + 1;
    while (after < body.length && body[after] == ' ') {
      after++;
    }
    if (after > column + 1) {
      return after;
    }
  }
  return column;
}

bool _isListItem(String body) => body.trimLeft().startsWith('- ');

bool _isBlankOrComment(String body) {
  final String trimmed = body.trim();
  return trimmed.isEmpty || trimmed.startsWith('#');
}

/// One line, its carriage return kept apart so the edit never touches it.
final class _Line {
  const _Line(this.body, this.carriage);

  /// The line without its carriage return.
  final String body;

  /// `\r` where the line had one, otherwise empty.
  final String carriage;

  /// This line carrying [body] instead.
  _Line withBody(String body) => _Line(body, carriage);
}

List<_Line> _lines(String content) => <_Line>[
  for (final String raw in content.split('\n'))
    raw.endsWith('\r') ? _Line(raw.substring(0, raw.length - 1), '\r') : _Line(raw, ''),
];

String _joined(List<_Line> lines) =>
    lines.map((_Line line) => '${line.body}${line.carriage}').join('\n');
