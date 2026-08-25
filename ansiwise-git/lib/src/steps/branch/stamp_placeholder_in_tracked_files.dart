import 'package:ansiwise_core/ansiwise_core.dart';

import 'stamp_selection.dart';

/// Replaces a literal in the tracked files of a checkout with a value this run holds.
///
/// A tree written to serve many installations carries a stand-in everywhere one installation would
/// carry something of its own, so that nothing in it belongs to anybody and every installation is
/// cut from the same source. This step is what turns one copy of such a tree into one installation.
/// It is run once per literal: the row names the literal, and names the answer that holds what goes
/// in its place.
///
/// **The set of files is FOUND, not named.** A content search over the tracked files answers with
/// the few that can possibly be in it, and git is what puts them back: an undo restores exactly the
/// paths this run rewrote and no other.
///
/// **Only the literal is replaced, and that is the whole rule.** There is nothing here that
/// recognises a domain or a branch, and adding one would be the defect. A value used as an
/// illustration — `example.com` in a comment, a help string, a user interface placeholder or a test
/// fixture — is a different literal, so it is never matched and never has to be told apart from a
/// value. The same holds for a label key written as `<domain>/<name>`: the part before the slash is
/// an identifier that nothing resolves and nothing addresses, and it survives for exactly the same
/// reason. A stamp that matched "anything domain-shaped" would rewrite both, and renaming a label
/// key reaches every selector and every binding that selects on it at once.
///
/// **[keys] is what narrows a common word to the value of a setting.** A branch name is an ordinary
/// English word that stands all over a tree, so replacing it wherever it occurs would rewrite it
/// inside a trailing comment and leave an installation branch explaining itself with a sentence its
/// own code contradicted. Where [keys] are named, the expression anchors on one of them at the start
/// of the line, allows the YAML anchor some of those lines carry (`targetRevision: &ref example`),
/// and rewrites the value alone. The lookahead after the literal refuses a longer value that merely
/// begins with it — `example-of-record` is not `example`. Where no [keys] are named, every
/// occurrence on the line is the value, which is what an unmistakable stand-in is.
///
/// **A line carrying [keepMarker] is never stamped.** What is marked is material every installation
/// shares and reads from one place, so pointing it at this installation's own branch would point it
/// at a branch that does not carry it. The marker itself is a word written into the tree being
/// stamped, so the row states it and this step carries no answer of its own about it.
///
/// **The replacement is an ANSWER or a RECORDED VALUE, and the row says which — never both.** What
/// one installation puts where the placeholder stands is the one value nobody can write into a file
/// that ships to all of them. Where the RUN holds it, the row carries the NAME of the question —
/// `value_answer: fqdn` — and the reading happens here; a run holding no answer of that name is
/// refused by name rather than stamping the literal out of every file and putting nothing in its
/// place. Where a FILE on the machine records it — a branch generated FROM another installation
/// inherits that installation's values, and asking for them again invites an answer that
/// contradicts what stands written — the row carries `value_file` and `value_key`, and the value is
/// read off a line of the shape `key: value` or `KEY=value`. Both at once is a pair that can
/// disagree and is refused as that.
///
/// **`value_rule` names one of the framework's derivation rules to work the replacement out of the
/// value, and it is a NAME out of a closed set, never an expression.** The case it exists for: the
/// file records a domain, and the placeholder stands where that domain's first label belongs.
/// Recording the label as well would be the same fact twice, and composing it in the program file
/// would make the file compute — the same reasoning the framework's answer derivations rest on, and
/// it is exactly those rules this reuses.
///
/// **Scripts and product material are excluded as a class, and that is load-bearing.** The
/// placeholder inside a script is never installation state — it is a guard, a fixture or a comment.
/// Two of them were rewritten before the exclusion existed: a script whose own guard compared against
/// the placeholder came out refusing the very domain it was being installed for, and a library whose
/// empty-value test read the placeholder came out producing hosts with no domain at all. Installation
/// state lives in values and config files.
///
/// **A script is recognised by what it is, not by what it is called.** A suffix list alone lets an
/// extensionless script through, and the stamp reached into a script again. The first line answers
/// for every one of those; the two suffixes stay for PowerShell, which carries no such line.
///
/// **The content search runs first and the first line second.** Only a file that carries the literal
/// can be in the answer, and that is a few dozen of several hundred. Testing the first line of every
/// tracked file instead costs one open per file, and that ordering was measured at eight and a half
/// seconds per call on Windows for a function every install and four checks run.
///
/// **The answer is read from the files rather than from a command having returned zero.** `sed`
/// exits zero whether or not its expression matched, and every failure of that shape reported success
/// while the file kept what it always held. A rewrite that silently matched nothing cannot report
/// itself as done here, and a second run finds nothing left to do.
final class StampPlaceholderInTrackedFiles extends ReversibleStep<List<String>> {
  /// Replaces [placeholder] with what this run answers, everywhere in [repository] that holds it.
  const StampPlaceholderInTrackedFiles({
    required this.repository,
    required this.refuseOnBranch,
    required this.placeholder,
    required this.keepMarker,
    required this.rule,
    this.valueAnswer,
    this.valueFile,
    this.valueKey,
    this.valueRule,
    this.tree = '',
    this.keys = const <String>[],
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  ///
  /// [tree] and [keys] are read as ABSENT-or-stated rather than as a value with a default. Each has
  /// an off state that is a real case — the whole checkout, and a literal that is itself the value —
  /// and a row wanting it leaves the key out. A default here would have been a value this package
  /// chose for the row rather than the neutral truth the mechanism already holds.
  factory StampPlaceholderInTrackedFiles.fromArguments(Arguments arguments) =>
      StampPlaceholderInTrackedFiles(
        repository: arguments.text('repository'),
        refuseOnBranch: arguments.text('refuse_on_branch'),
        placeholder: arguments.text('placeholder'),
        valueAnswer: arguments.optionalText('value_answer'),
        valueFile: arguments.optionalText('value_file'),
        valueKey: arguments.optionalText('value_key'),
        valueRule: arguments.optionalText('value_rule'),
        keepMarker: arguments.text('keep_marker'),
        tree: arguments.optionalText('tree') ?? '',
        keys: arguments.has('keys') ? arguments.textList('keys') : const <String>[],
        rule: StampSelection(
          excludedSegments: arguments.textList('excluded_segments'),
          excludedNames: arguments.textList('excluded_names'),
          scriptSuffixes: arguments.textList('script_suffixes'),
        ),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
    ArgumentSpec(
      name: 'refuse_on_branch',
      kind: ArgumentKind.text,
      describes:
          'the branch this row refuses to run on: a checkout standing on it is the source every '
          'installation is cut from, and not one installation',
    ),
    ArgumentSpec(
      name: 'placeholder',
      kind: ArgumentKind.text,
      describes:
          'the literal this checkout carries wherever one installation would carry a value of its '
          'own — an unmistakable stand-in, or a common word narrowed by the keys below',
    ),
    // The NAME of the answer, never the value. What a stamp writes is the one thing nobody can put
    // in a file that ships to every installation, so the row carries the name of the question and
    // the reading happens here — the same shape the row that cuts the branch uses, so the branch
    // and everything stamped into it are named from one place.
    ArgumentSpec(
      name: 'value_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer this run reads the replacement out of — write "fqdn" here and '
          'every placeholder is replaced by whatever this run answered for "fqdn". Leave it off '
          'where value_file records the value instead',
    ),
    // The OTHER source, for a value the run does not hold because another installation already
    // decided it: a file on this machine records it, and the row names the file and the key. One
    // source per row, never both — the check refuses the pair by name.
    ArgumentSpec(
      name: 'value_file',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the settings file on this machine the replacement is recorded in, read as one '
          '"key: value" or "KEY=value" line per key. Leave it off where value_answer names the '
          'value instead',
    ),
    ArgumentSpec(
      name: 'value_key',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the key inside value_file whose value is the replacement',
    ),
    ArgumentSpec(
      name: 'value_rule',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the name of one of the framework\'s single-source derivation rules, applied to the '
          'value before it is stamped — first_dns_label_of turns a recorded domain into its short '
          'name. Leave it off to stamp the value as it stands',
    ),
    // The marker is a word somebody wrote into the product's own files, so it is that product's and
    // not this step's. A default here would make a line reading somebody else's word survive a
    // stamp on a tree that never agreed to it.
    ArgumentSpec(
      name: 'keep_marker',
      kind: ArgumentKind.text,
      describes:
          'the trailing comment that exempts a line from every stamp, as the tree being generated '
          'writes it — a line carrying it is product every installation shares',
    ),
    // Absent-or-stated, and no default. Both have an off state that is a real case rather than a
    // value: the whole checkout, and a literal that is itself the value wherever it stands. A row
    // wanting either leaves the key out.
    ArgumentSpec(
      name: 'tree',
      kind: ArgumentKind.text,
      describes:
          'the directory the search is limited to, left out for the whole checkout — a layout of '
          'the tree being generated rather than a value of this installation',
      required: false,
    ),
    ArgumentSpec(
      name: 'keys',
      kind: ArgumentKind.textList,
      describes:
          'the keys whose value is replaced, left out where every occurrence on the line is the '
          'value — a common word that also stands in prose needs the key in front of it',
      required: false,
    ),
    // The three exclusion lists carry no default either. Which directories hold product material,
    // which file declares something about the stamp and which suffixes name a script are facts of
    // the tree being generated, and a value here would be this step deciding them for whatever tree
    // it is pointed at.
    ArgumentSpec(
      name: 'excluded_segments',
      kind: ArgumentKind.textList,
      describes:
          'path segments whose contents are product material rather than installation state — a '
          'segment and not a prefix, so a directory of that name is excluded at any depth',
    ),
    ArgumentSpec(
      name: 'excluded_names',
      kind: ArgumentKind.textList,
      describes:
          'files excluded by their name, because each declares something about the stamp and '
          'would read as its own opposite once stamped',
    ),
    ArgumentSpec(
      name: 'script_suffixes',
      kind: ArgumentKind.textList,
      describes:
          'the suffixes of the scripts that carry no first line to recognise them by — a script '
          'is never stamped, whatever it is called',
    ),
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Empty: which answer it reads is what the row says under `value_answer`, so a list here would
  /// name one product's question. The row that declares the answer statically is the gate at the
  /// head of the program, which is what keeps the resolver refusing a program that stopped
  /// declaring it.
  static const List<String> answers = <String>[];

  /// The rule this run selects files by, built from the row's exclusion lists.
  ///
  /// It carries no default, and that is the whole of it: which directories hold material rather
  /// than state is a fact of the tree being stamped, so a value chosen here would be this package
  /// deciding it for whatever tree it is pointed at.
  final StampSelection rule;

  /// The trailing comment that exempts a line from every stamp, as the row states it.
  final String keepMarker;

  /// The name of the answer the replacement is read out of, or null where a file records it.
  final String? valueAnswer;

  /// The settings file the replacement is recorded in, or null where an answer holds it.
  final String? valueFile;

  /// The key inside [valueFile] whose value is the replacement.
  final String? valueKey;

  /// The name of the derivation rule applied to the value, or null to stamp it as it stands.
  final String? valueRule;

  /// The checkout being stamped.
  final String repository;

  /// The branch this step refuses to run on, as the row names it.
  final String refuseOnBranch;

  /// The literal this checkout carries wherever one installation would carry a value of its own.
  final String placeholder;

  /// The directory the search is limited to, or empty for the whole checkout.
  final String tree;

  /// The keys whose value is replaced, or empty where every occurrence on the line is.
  final List<String> keys;

  /// This row refuses while [refuseOnBranch] is checked out, and only a step BEFORE it moves off
  /// that branch.
  ///
  /// Measured on a machine rather than reasoned about: a program that cuts a branch and then stamps
  /// it reported the stamp as failed under `--mode test`, because in that mode the branch is never
  /// actually cut and the refusal is still true. That answer is honest about the machine and wrong
  /// about the program, so the record marks it DECLARED instead of counting it against the run.

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  bool get restsOnAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? replacement = await _replacement(context);
    if (replacement == null) {
      return CheckResult.blocked(await _whyValueless(context));
    }

    final String? head = await _head(context);
    if (head == refuseOnBranch) {
      return CheckResult.blocked(
        '"$refuseOnBranch" is checked out, and this row refuses to stamp it: doing so would '
        "hand this installation's own values to every installation cut from it afterwards — "
        'cut the branch first',
      );
    }

    final Map<String, String> left = await _stampable(context, replacement);
    if (left.isEmpty) {
      return CheckResult.satisfied(
        'no file $_under that holds installation state carries $placeholder',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? replacement = await _replacement(context);
    // Answered rather than thrown. A plan is what an operator reads to decide whether to let the run
    // happen, and a plan that failed to be produced tells them nothing about what would be done.
    if (replacement == null) {
      return StepPlan.nothing(await _whyValueless(context));
    }

    final Map<String, String> left = await _stampable(context, replacement);
    for (final String path in left.keys) {
      context.log.info('$path would have $placeholder replaced by $replacement');
    }
    final List<String> lines = <String>[
      for (final String content in left.values) ..._changing(content, replacement),
    ];
    // One step here rewrites many files and a plan carries one path, so the path is the tree and the
    // difference is the set of lines that change — which is what an operator reads a plan for.
    return StepPlan.diff(
      _where,
      before: lines.join('\n'),
      after: lines.map((String line) => _stamped(line, replacement)).join('\n'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? replacement = await _replacement(context);
    if (replacement == null) {
      // The engine applies a step only after its check answered ready, and that check refuses this
      // by name — so reaching here is a call out of order. Stamping anyway would take the
      // placeholder out of every file it touched and put nothing where it stood.
      throw StateError(await _whyValueless(context));
    }

    final Map<String, String> stampable = await _stampable(context, replacement);
    for (final MapEntry<String, String> file in stampable.entries) {
      final String after = file.value
          .split('\n')
          .map((String line) => _stamped(line, replacement))
          .join('\n');
      await context.files.write(
        '$repository/${file.key}',
        after,
        mode: _trackedFile,
        elevated: elevated,
      );
    }
  }

  /// Which files this run is about to stamp, as the checkout names them.
  ///
  /// Read before apply, because afterwards they carry the replacement and a search for it answers
  /// with every file that carries it — the ones this step wrote and any that already held it.
  /// Restoring the whole tree instead would take back every other change standing in it, including
  /// what a later step stamps and anything an operator edited on the branch.
  ///
  /// A run holding no answer of the row's name stamps nothing, so there is nothing to take back.
  @override
  Future<List<String>> capture(StepContext context) async {
    if (await _replacement(context) case final String replacement) {
      return (await _stampable(context, replacement)).keys.toList();
    }
    return const <String>[];
  }

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    if (captured.isEmpty) {
      return;
    }
    final List<String> argv = <String>['-C', repository, 'checkout', '--', ...captured];
    // The take-back writes the same files the apply wrote through the files port, so it reaches for
    // them the same way. The plain constructor fixes the elevation to false and cannot carry the
    // row's answer at all.
    final CommandResult restored = await context.shell.run(
      Command.detailed('git', arguments: argv, elevated: elevated),
    );
    if (!restored.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: restored.exitCode,
        stdout: '',
        stderr: restored.stderr,
      );
    }
  }

  /// The files that hold installation state and still carry a line this stamp would rewrite.
  ///
  /// This is also the postcondition: it is read from the files rather than from a command having
  /// returned zero, so a rewrite that silently matched nothing cannot report itself as done.
  ///
  /// The order of the tests is the point. The content search has already narrowed several hundred
  /// tracked files to the few that can be in the answer; the name tests cost nothing and run next;
  /// the file is opened once, and only a file that really carries the literal is asked what it is.
  Future<Map<String, String>> _stampable(StepContext context, String replacement) async {
    final Map<String, String> stampable = <String, String>{};
    for (final String path in await _search(context)) {
      if (rule.excludesByName(path)) {
        continue;
      }
      // A tracked path the search names is not necessarily a file that is there: reducing the branch
      // to one stage removes whole trees while git goes on tracking them until the commit.
      final String full = '$repository/$path';
      if (!await context.files.exists(full, elevated: elevated)) {
        continue;
      }
      final String content = await context.files.read(full, elevated: elevated);
      // What the name test above already settled is settled again here and costs nothing; what it
      // could not settle — a first line that makes this a script whatever it is called — is settled
      // by the same object the gate asks, so the two cannot answer differently.
      if (!rule.holdsStampableValue(path, content)) {
        continue;
      }
      if (_changing(content, replacement).isEmpty) {
        continue;
      }
      stampable[path] = content;
    }
    return stampable;
  }

  /// Every tracked file carrying [placeholder], as paths relative to the top of the checkout.
  Future<List<String>> _search(StepContext context) async {
    final List<String> argv = <String>[
      '-C',
      repository,
      'grep',
      '--full-name',
      '--files-with-matches',
      '--fixed-strings',
      '-e',
      placeholder,
      if (tree.isNotEmpty) ...<String>['--', tree],
    ];
    // The search reads the same working tree the loop below reads through the files port. Asked as
    // the operator over a checkout root owns, git answers "Permission denied" at exit code above
    // one, which the throw below turns into a failure rather than into an empty answer.
    final CommandResult found = await context.shell.run(
      Command.observing('git', arguments: argv, elevated: elevated),
    );
    // A content search answers one when it found nothing, which is an answer and not a failure.
    // Anything above that is a search that could not be carried out, and treating it as "no files"
    // would report a tree as stamped because nobody could look at it.
    if (found.exitCode > 1) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: found.exitCode,
        stdout: '',
        stderr: found.stderr,
      );
    }
    return found.trimmed.isEmpty
        ? const <String>[]
        : found.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  /// The lines of [content] this stamp would rewrite, in the order they stand in.
  List<String> _changing(String content, String replacement) => <String>[
    for (final String line in content.split('\n'))
      if (_stamped(line, replacement) != line) line,
  ];

  /// [line] with its value replaced by [replacement], or [line] itself when it is not one to stamp.
  String _stamped(String line, String replacement) {
    if (line.contains(keepMarker)) {
      return line;
    }
    if (keys.isEmpty) {
      return line.replaceAll(placeholder, replacement);
    }
    return line.replaceFirstMapped(_pattern, (Match match) => '${match.group(1)}$replacement');
  }

  /// What this run replaces every occurrence by, from whichever source the row named.
  ///
  /// Null where the row misdeclared its source, where the source holds nothing, or where it was
  /// left blank — [_whyValueless] says which. Nothing stands in for it: a stamp with an empty
  /// replacement takes the literal out of every file it touches and leaves the value that literal
  /// stood for nowhere at all.
  Future<String?> _replacement(StepContext context) async {
    if (_misdeclared != null) {
      return null;
    }
    final String? raw = valueAnswer != null
        ? context.answers.optionalText(valueAnswer!)
        : await _recorded(context);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    if (valueRule case final String named) {
      // The rule was vetted by [_misdeclared], so this cannot be null here.
      return DerivationRule.named(named)!.applyTo(raw);
    }
    return raw;
  }

  /// What is wrong with the row's own declaration of its value source, or null where it is sound.
  ///
  /// A property of the ROW and not of any machine, so it is answered without one — and answered
  /// first, because a row that says two contradictory things must not be read as either of them.
  String? get _misdeclared {
    if (valueAnswer != null && valueFile != null) {
      return 'this row names an answer AND a file for the value every "$placeholder" is replaced '
          'by, and two statements of one value is a pair that can disagree — keep whichever states '
          'the truth and drop the other';
    }
    if (valueAnswer == null && valueFile == null) {
      return 'this row names no source at all for the value every "$placeholder" is replaced by — '
          'write value_answer for a value the run holds, or value_file and value_key for one a '
          'file on this machine records';
    }
    if (valueFile != null && (valueKey == null || valueKey!.isEmpty)) {
      return 'this row reads the value out of $valueFile and names no value_key, so nothing says '
          'which line of it holds the value';
    }
    if (valueRule case final String named) {
      final DerivationRule? rule = DerivationRule.named(named);
      if (rule == null) {
        return '"$named" is not a derivation rule — it is one of '
            '${DerivationRule.allWritten.join(', ')}';
      }
      if (rule.sources != 1) {
        return '"$named" reads a pair of answers, and a stamp holds one value to work its '
            'replacement out of';
      }
    }
    return null;
  }

  /// The value the named file records under the named key, or null where it records none.
  Future<String?> _recorded(StepContext context) async {
    if (!await context.files.exists(valueFile!, elevated: elevated)) {
      return null;
    }
    final String content = await context.files.read(valueFile!, elevated: elevated);
    final RegExp line = RegExp('^[ \\t]*${RegExp.escape(valueKey!)}[ \\t]*[:=][ \\t]*(.*)\$');
    for (final String each in content.split('\n')) {
      final RegExpMatch? match = line.firstMatch(each.trimRight());
      if (match == null) {
        continue;
      }
      String value = match.group(1)!.trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  /// Why no replacement could be produced, said so an operator can act on the right half.
  Future<String> _whyValueless(StepContext context) async {
    if (_misdeclared case final String wrong) {
      return wrong;
    }
    if (valueAnswer case final String name) {
      return 'this run holds no answer called "$name", and that is where this row says the value '
          'every "$placeholder" is replaced by comes from';
    }
    if (!await context.files.exists(valueFile!, elevated: elevated)) {
      return '$valueFile is not there, and it is where this row says the value every '
          '"$placeholder" is replaced by is recorded';
    }
    return '$valueFile records no value under "$valueKey", and that is where this row says the '
        'value every "$placeholder" is replaced by comes from';
  }

  /// One of [keys] at the start of the line, the anchor some lines carry, and then the value itself.
  ///
  /// The value stops at its own word: the lookahead refuses a longer value that merely begins with
  /// the literal, which a word boundary would have let through.
  RegExp get _pattern => RegExp(
    '^([ \\t]*(?:-[ \\t]+)?(?:${keys.map(RegExp.escape).join('|')}):[ \\t]*'
    '(?:&[^ \\t]+[ \\t]+)?)${RegExp.escape(placeholder)}(?![\\w./-])',
  );

  /// The one path a plan carries for a step that rewrites many files.
  String get _where => tree.isEmpty ? repository : '$repository/$tree';

  /// How a message names the part of the checkout this row is about.
  String get _under => tree.isEmpty ? 'in the checkout' : 'under $tree/';

  /// Which branch the checkout stands on, or null where git could not say.
  ///
  /// Read at this row's own elevation, like everything else this step reads out of the checkout.
  /// Null is what the guard above compares against `refuseOnBranch`, so a reading refused for want
  /// of root would not refuse the stamp — it would let it run on the branch the row named.
  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
        elevated: elevated,
      ),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  /// `0644` — a values, config or manifest file everything in the tree reads.
  static const int _trackedFile = 0x1a4;
}
