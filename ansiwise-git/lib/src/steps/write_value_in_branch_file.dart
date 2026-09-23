import 'package:ansiwise_core/ansiwise_core.dart';

/// Writes one key's value into one tracked file of the branch this checkout stands on.
///
/// The writing half of `measure_value_in_branch_file`, and deliberately its mirror: the same
/// checkout, the same path with the same two slots, the same shape of line. What one reads, the
/// other writes, so a value recorded by an operation and read by the next one cannot come to be two
/// different ideas of where it lives.
///
/// **THE VALUE IS A FACT OF ONE RUN AND NEVER COMES FROM THE PROGRAM FILE.** What is written here is
/// a fact of one run against one installation — which release a cluster follows, which address it
/// was given — and a program file ships to every installation. So the row says where the run holds
/// it: an ANSWER, named in `value_answer`, or the MEASUREMENT an earlier row of the same program
/// took, written `value: {measured: <name>}`. Exactly one of the two: a row naming both, or neither,
/// is refused before the checkout is asked anything.
///
/// **The line is replaced where it stands, and added only where the file has none.** A file that
/// already records the key is edited in place, so the order a person put it in survives. One that
/// records none gains the line: a key at the head of the file at its end, a key inside a block
/// directly under the line that opens the block. Appending unconditionally would leave two lines for
/// one key, and what reads them takes one — so the next run would decide the question again,
/// silently.
///
/// **It writes the WORKING TREE and records nothing.** Committing is its own act with its own
/// reasons — which paths, which message, whether a push follows — so a row that commits belongs
/// after this one and says so itself. What this leaves behind is a changed file, which is what an
/// operator reviews before anything of it leaves the machine.
final class WriteValueInBranchFile extends ReversibleStep<String?> {
  /// Writes [key] into [path] of the checkout at [repository], from the answer [valueAnswer] names
  /// or from the measured [value].
  const WriteValueInBranchFile({
    required this.repository,
    required this.path,
    required this.key,
    required this.fileMode,
    this.valueAnswer,
    this.value,
    this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory WriteValueInBranchFile.fromArguments(Arguments arguments) => WriteValueInBranchFile(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    key: arguments.text('key'),
    valueAnswer: arguments.optionalText('value_answer'),
    value: arguments.optionalText('value'),
    fileMode: arguments.integer('file_mode'),
    runAnswer: arguments.optionalText('run_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose branch carries the file the value is recorded in',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the file inside the checkout, as the branch tracks it. It may carry the slot <branch> '
          'where the name of the branch this checkout stands on belongs, and the slot named by '
          'run_answer where that answer\'s value belongs — the same two the reading step fills',
    ),
    ArgumentSpec(
      name: 'key',
      kind: ArgumentKind.text,
      describes: 'the key whose value is written, on a line of the shape "key: value"',
    ),
    ArgumentSpec(
      name: 'value_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer holding what to write. Named rather than written, because what '
          'is recorded here is a fact of one run against one installation and this file ships to '
          'every installation. Give this or value, never both',
    ),
    ArgumentSpec(
      name: 'value',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'what to write itself — written as {measured: <name>} off the row that took it from the '
          'machine earlier in this program, never as a value in the file, for the reason '
          'value_answer gives. Give this or value_answer, never both',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 0,
        most: 4095,
        because:
            'a permission mode is twelve bits, so 4095 is 0o7777 and nothing outside it is a mode',
      ),
      describes:
          'the permissions the file is written back with, as the number the machine stores — 420 '
          'is the mode of a file anyone on the machine may read, 384 of one only its owner may. '
          'Stated rather than kept, because a step that preserved whatever it found would carry a '
          'wrong mode forward for ever instead of putting it right',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'path — write "fqdn" here and every "<fqdn>" in it is filled with this run\'s fqdn, '
          'which is how a file carrying ANOTHER installation\'s name is written on this branch',
    ),
  ];

  /// The checkout.
  final String repository;

  /// The file inside it, before any slot is filled.
  final String path;

  /// The key whose value is written.
  final String key;

  /// The name of the answer holding what to write, or null where the row gives [value] instead.
  final String? valueAnswer;

  /// What to write, as an earlier row measured it, or null where the row names [valueAnswer].
  final String? value;

  /// The permissions the file is written back with.
  final int fileMode;

  /// WHICH answer fills the slot spelled the same way in the path, or null where it carries none.
  final String? runAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Target target = await _target(context);
    if (target.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? held = _valueIn(target.contents!);
    return held == target.wanted
        ? CheckResult.satisfied('${target.file} records $key: ${target.wanted}')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Target target = await _target(context);
    if (target.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.diff(target.file!, before: target.contents!, after: target.written!);
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Target target = await _target(context);
    if (target.refusal case final String refusal) {
      throw StateError(refusal);
    }
    await context.files.write('$repository/${target.file}', target.written!, mode: fileMode);
  }

  /// The file as it stood before this ran, or null where there was none to change.
  @override
  Future<String?> capture(StepContext context) async {
    final _Target target = await _target(context);
    return target.contents;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    final _Target target = await _target(context);
    if (target.file case final String file) {
      await context.files.write('$repository/$file', captured, mode: fileMode);
    }
  }

  /// Which file this row means, what it holds, and what is to stand in it.
  Future<_Target> _target(StepContext context) async {
    if (_shapeRefusal case final String refusal) {
      return _Target.unreachable(refusal);
    }
    final CommandResult head = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
      ),
    );
    if (!head.ok || head.trimmed.isEmpty || head.trimmed == 'HEAD') {
      return const _Target.unreachable(
        'this checkout has no branch checked out, and what is written here is what a branch '
        'states about itself',
      );
    }
    final String named = filledSlots(path, <String, String>{
      'branch': head.trimmed,
      ..._answerSlot(context),
    });
    if (leftoverSlotIn(named) case final String leftover) {
      return _Target.unreachable(
        'the path "$path" still carries "$leftover" after filling <branch> and the run\'s own '
        'answer — the two slots this step fills — so the row names a file nothing can resolve',
      );
    }
    final String? wanted = (value ?? context.answers.optionalText(valueAnswer!))?.trim();
    if (wanted == null || wanted.isEmpty) {
      final String absent = value == null
          ? 'this run holds no answer called "$valueAnswer"'
          : 'the value this row was handed is empty';
      return _Target.unreachable(
        '$absent, and that is where this row says the value of "$key" comes from — writing an '
        'empty one would record an absence as a value',
      );
    }
    // THE WORKING TREE AND NOT THE COMMIT. What is read is the file as it stands, because that is
    // what is written, and a run that has already changed it must find its own change rather than
    // the state the branch last recorded — or a second check would report work to do for ever.
    if (!await context.files.exists('$repository/$named')) {
      return _Target.unreachable(
        'the checkout carries no file at $named, and it is where this row says the value of "$key" '
        'is recorded — the file is written by whatever generated this branch, so a run reaching '
        'here without it has that generation still to do',
      );
    }
    final String contents = await context.files.read('$repository/$named');
    // A KEY WITH NO PLACE IN THIS FILE IS SAID, NOT PASSED OVER. Writing the file back unchanged
    // would be a green step over a file that says what it said before.
    final String? written = _withValue(contents, wanted);
    if (written == null) {
      return _Target.unreachable(
        '$named carries no "$key" to write into: the path names a block this file does not open, '
        'and a key inside a block is never written at the head of the file — there it would mean '
        'something else, and the file would answer one question twice',
      );
    }
    return _Target(file: named, contents: contents, wanted: wanted, written: written);
  }

  /// Why this ROW cannot be read, whatever checkout it runs against, or null when it can.
  String? get _shapeRefusal {
    if (value != null && valueAnswer != null) {
      return 'this row names both value and value_answer, which are two answers to what "$key" '
          'holds. Whichever a reader took first would be the one that decided, and the other would '
          'sit there looking like it had been read';
    }
    if (value == null && valueAnswer == null) {
      return 'this row names neither value nor value_answer, so nothing says what "$key" holds';
    }
    return null;
  }

  /// The one slot value the row's answer supplies, or nothing where it names none.
  Map<String, String> _answerSlot(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return <String, String>{name: value};
      }
    }
    return const <String, String>{};
  }

  /// The segments of [key]: one for a key at the head of a line, more for one inside a block.
  ///
  /// **A DOT IS A PATH AND NEVER PART OF A NAME.** No key this platform writes carries one, and a
  /// step that had to be told which of the two a dot meant would be told it in a program file — one
  /// more thing to state, and one more thing to state wrongly.
  List<String> get _path => key.split('.');

  /// Which line of [lines] carries this key, or -1 where none does.
  ///
  /// **WHY THIS WALKS RATHER THAN SEARCHES.** Matching the key at the HEAD of a line only fails
  /// where a file carries it inside a block, and the write then appends a second key at the head of
  /// the file instead. A values file then carries `clusterIssuer` twice — nested under `global:`
  /// with the old value and at the top with the new one — and every chart goes on reading the old.
  /// Nothing says so; the run is green.
  ///
  /// So a path is walked block by block: each segment is looked for among the KEYS of the block its
  /// parent opened, which stand at that block's own indentation in the region of deeper-indented
  /// lines following the parent's own line. A line of the same name further in belongs to a block
  /// inside it and is no match, and a path whose parent block is absent is no match either.
  int _lineOf(List<String> lines) => _opening(lines, _path.length);

  /// The line of [lines] carrying the first [segments] segments of this key's path, or -1 where one
  /// of them is absent.
  int _opening(List<String> lines, int segments) {
    int at = -1;
    for (int segment = 0; segment < segments; segment++) {
      at = _keyIn(lines, at, _path[segment]);
      if (at < 0) {
        return -1;
      }
    }
    return at;
  }

  /// The line opening [name] among the keys of the block opened at [parent], or -1.
  ///
  /// [parent] is -1 for the head of the file, whose keys stand at no indent at all. A block's keys
  /// stand at the indentation of its first line.
  int _keyIn(List<String> lines, int parent, String name) {
    final (int from, int until) = _blockOf(lines, parent);
    final int? depth = parent < 0 ? 0 : _firstIndentIn(lines, from, until);
    for (int i = from; i < until; i++) {
      final String bare = lines[i].trimLeft();
      if (bare.isEmpty || bare.startsWith('#') || _indentOf(lines[i]) != depth) {
        continue;
      }
      if (bare.startsWith('$name:')) {
        return i;
      }
    }
    return -1;
  }

  /// The lines `[from, until)` of the block opened at [parent], or the whole file for -1.
  (int, int) _blockOf(List<String> lines, int parent) => parent < 0
      ? (0, lines.length)
      : (parent + 1, _endOfBlock(lines, parent + 1, _indentOf(lines[parent])));

  /// Where the block opened at [outer] ends: the first line at that depth or shallower, or the end.
  int _endOfBlock(List<String> lines, int from, int outer) {
    for (int i = from; i < lines.length; i++) {
      final String bare = lines[i].trimLeft();
      if (bare.isEmpty || bare.startsWith('#')) {
        continue;
      }
      if (_indentOf(lines[i]) <= outer) {
        return i;
      }
    }
    return lines.length;
  }

  /// How far the first line in `[from, until)` that is not blank or a comment is indented, or null
  /// where there is none.
  int? _firstIndentIn(List<String> lines, int from, int until) {
    for (int i = from; i < until; i++) {
      final String bare = lines[i].trimLeft();
      if (bare.isNotEmpty && !bare.startsWith('#')) {
        return _indentOf(lines[i]);
      }
    }
    return null;
  }

  /// Whether the line at [at] opens a block of keys: nothing but a comment follows its colon, and
  /// what stands under it is not an entry of a list.
  ///
  /// A line carrying its own value — `global: {}` — or a list is no block a key can stand in, and a
  /// key written under it makes a file no reader parses.
  bool _opensKeys(List<String> lines, int at) {
    final String bare = lines[at].trimLeft();
    final String rest = bare.substring(bare.indexOf(':') + 1).trim();
    if (rest.isNotEmpty && !rest.startsWith('#')) {
      return false;
    }
    for (int i = at + 1; i < lines.length; i++) {
      final String next = lines[i].trimLeft();
      if (next.isEmpty || next.startsWith('#')) {
        continue;
      }
      final bool listed = next == '-' || next.startsWith('- ');
      return !listed || _indentOf(lines[i]) < _indentOf(lines[at]);
    }
    return true;
  }

  /// How far [line] is indented.
  int _indentOf(String line) => line.length - line.trimLeft().length;

  /// What [contents] records under this key, or null where it records nothing.
  String? _valueIn(String contents) {
    final List<String> lines = contents.split('\n');
    final int at = _lineOf(lines);
    if (at < 0) {
      return null;
    }
    return lines[at].trimLeft().substring(_path.last.length + 1).trim();
  }

  /// [contents] with this key holding [value], or null where the file has no place for it.
  ///
  /// The line is replaced where it stands, keeping the indentation it already has; a key at the head
  /// of the file that is not there is appended.
  ///
  /// **A KEY INSIDE A BLOCK IS INSERTED INTO THAT BLOCK AND NEVER APPENDED.** Appending would put it
  /// at the head of the file, where it means something else, and the file would then say the same
  /// thing twice with two values. It goes directly under the line that opens its block, at the
  /// indentation of the block's first line — two deeper than the opening line where the block holds
  /// nothing yet.
  ///
  /// **A BLOCK THE FILE DOES NOT OPEN IS NEVER INVENTED.** Where the parent block is absent, or its
  /// line holds a value or a list rather than keys, this is null and the step refuses — a refusal an
  /// operator reads, instead of a structure nobody wrote or a file nothing parses.
  String? _withValue(String contents, String value) {
    final List<String> lines = contents.split('\n');
    final int at = _lineOf(lines);
    if (at >= 0) {
      lines[at] = '${' ' * _indentOf(lines[at])}${_path.last}: $value';
      return lines.join('\n');
    }
    if (_path.length == 1) {
      final String body = contents.endsWith('\n') || contents.isEmpty ? contents : '$contents\n';
      return '$body$key: $value\n';
    }
    final int parent = _opening(lines, _path.length - 1);
    if (parent < 0 || !_opensKeys(lines, parent)) {
      return null;
    }
    final (int from, int until) = _blockOf(lines, parent);
    final int indent = _firstIndentIn(lines, from, until) ?? _indentOf(lines[parent]) + 2;
    lines.insert(from, '${' ' * indent}${_path.last}: $value');
    return lines.join('\n');
  }
}

/// Which file a row means, what stands in it and what is to stand in it, or why none of that can be
/// had.
final class _Target {
  const _Target({
    required String this.file,
    required String this.contents,
    required String this.wanted,
    required String this.written,
  }) : refusal = null;

  const _Target.unreachable(String this.refusal)
    : file = null,
      contents = null,
      wanted = null,
      written = null;

  final String? file;
  final String? contents;
  final String? wanted;
  final String? written;
  final String? refusal;
}
