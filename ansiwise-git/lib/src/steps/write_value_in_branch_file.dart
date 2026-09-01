import 'package:ansiwise_core/ansiwise_core.dart';

/// Writes one key's value into one tracked file of the branch this checkout stands on.
///
/// The writing half of `measure_value_in_branch_file`, and deliberately its mirror: the same
/// checkout, the same path with the same two slots, the same shape of line. What one reads, the
/// other writes, so a value recorded by an operation and read by the next one cannot come to be two
/// different ideas of where it lives.
///
/// **THE VALUE COMES FROM AN ANSWER AND NEVER FROM THIS FILE.** What is written here is a fact of
/// one run against one installation — which release a cluster follows, which address it was given —
/// and a program file ships to every installation. So the row names the ANSWER, and the value
/// reaches the file through the run.
///
/// **The line is replaced where it stands, and appended only where the file has none.** A file that
/// already records the key is edited in place, so the order a person put it in survives; one that
/// records none gains the line at the end. Appending unconditionally would leave two lines for one
/// key, and what reads them takes one — so the next run would decide the question again, silently.
///
/// **It writes the WORKING TREE and records nothing.** Committing is its own act with its own
/// reasons — which paths, which message, whether a push follows — so a row that commits belongs
/// after this one and says so itself. What this leaves behind is a changed file, which is what an
/// operator reviews before anything of it leaves the machine.
final class WriteValueInBranchFile extends ReversibleStep<String?> {
  /// Writes [key] into [path] of the checkout at [repository], from the answer [valueAnswer] names.
  const WriteValueInBranchFile({
    required this.repository,
    required this.path,
    required this.key,
    required this.valueAnswer,
    required this.fileMode,
    this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory WriteValueInBranchFile.fromArguments(Arguments arguments) => WriteValueInBranchFile(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    key: arguments.text('key'),
    valueAnswer: arguments.text('value_answer'),
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
      describes:
          'the name of the answer holding what to write. Named rather than written, because what '
          'is recorded here is a fact of one run against one installation and this file ships to '
          'every installation',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
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

  /// The name of the answer holding what to write.
  final String valueAnswer;

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
    return StepPlan.diff(
      target.file!,
      before: target.contents!,
      after: _withValue(target.contents!, target.wanted!),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Target target = await _target(context);
    if (target.refusal case final String refusal) {
      throw StateError(refusal);
    }
    // A PATH THAT IS NOT THERE IS SAID, NOT PASSED OVER. `_withValue` leaves the file untouched
    // where a nested key cannot be reached, because the alternative — appending it at the head of
    // the file — is what once made a values file carry the same key twice with two different
    // values, silently, with every chart reading the wrong one. Writing it back unchanged would be
    // the same silence in a quieter form: a green step over a file that says what it said before.
    //
    // The question asked is whether the LINE exists, never whether the contents changed: a file
    // already carrying the wanted value changes by nothing either, and that one is finished rather
    // than broken.
    if (_path.length > 1 && _lineOf(target.contents!.split('\n')) < 0) {
      throw StateError(
        '${target.file} carries no "$key" to write into: the path names a block this file does not '
        'open, and a key inside a block is never appended — at the head of the file it would mean '
        'something else, and the file would answer one question twice',
      );
    }
    final String written = _withValue(target.contents!, target.wanted!);
    await context.files.write('$repository/${target.file}', written, mode: fileMode);
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
    final String? wanted = context.answers.optionalText(valueAnswer)?.trim();
    if (wanted == null || wanted.isEmpty) {
      return _Target.unreachable(
        'this run holds no answer called "$valueAnswer", and that is where this row says the value '
        'of "$key" comes from — writing an empty one would record an absence as a value',
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
    return _Target(
      file: named,
      contents: await context.files.read('$repository/$named'),
      wanted: wanted,
    );
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
  /// **WHY THIS WALKS RATHER THAN SEARCHES.** The first shape of this step matched the key at the
  /// HEAD of a line only — and where a file carried it inside a block, the search failed and the
  /// write appended a second key at the head of the file instead. Measured on apps5 on 2026-09-01: a
  /// values file ended up carrying `clusterIssuer` twice, nested under `global:` with the old value
  /// and at the top with the new one, and every chart went on reading the old. Nothing said so; the
  /// run was green.
  ///
  /// So a path is walked block by block: each segment is looked for INSIDE the block its parent
  /// opened, which is the region of deeper-indented lines following the parent's own line. A segment
  /// found at the wrong depth is no match, and a path whose parent block is absent is no match
  /// either — the write refuses rather than inventing a structure.
  int _lineOf(List<String> lines) {
    int from = 0;
    int until = lines.length;
    int depth = -1;
    for (int segment = 0; segment < _path.length; segment++) {
      final int found = _headOf(lines, _path[segment], from, until, depth);
      if (found < 0) {
        return -1;
      }
      if (segment == _path.length - 1) {
        return found;
      }
      depth = _indentOf(lines[found]);
      from = found + 1;
      until = _endOfBlock(lines, from, depth);
    }
    return -1;
  }

  /// The line in `[from, until)` opening [name] one level inside a parent indented [outer], or -1.
  ///
  /// [outer] is -1 for the head of the file, where a key stands at no indent at all.
  int _headOf(List<String> lines, String name, int from, int until, int outer) {
    for (int i = from; i < until; i++) {
      final String bare = lines[i].trimLeft();
      if (bare.isEmpty || bare.startsWith('#')) {
        continue;
      }
      final int indent = _indentOf(lines[i]);
      if (outer < 0 ? indent != 0 : indent <= outer) {
        continue;
      }
      if (bare.startsWith('$name:')) {
        return i;
      }
    }
    return -1;
  }

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

  /// [contents] with this key holding [value]: the line replaced where it stands, keeping the
  /// indentation it already has — or, for a key at the head of the file that is not there, appended.
  ///
  /// **A KEY INSIDE A BLOCK IS NEVER APPENDED.** Appending would put it at the head of the file,
  /// where it means something else, and the file would then say the same thing twice with two
  /// values. Where such a path cannot be found this returns [contents] unchanged, and the step
  /// reports it — a refusal an operator reads, instead of a second key nobody sees.
  String _withValue(String contents, String value) {
    final List<String> lines = contents.split('\n');
    final int at = _lineOf(lines);
    if (at >= 0) {
      lines[at] = '${' ' * _indentOf(lines[at])}${_path.last}: $value';
      return lines.join('\n');
    }
    if (_path.length > 1) {
      return contents;
    }
    final String body = contents.endsWith('\n') || contents.isEmpty ? contents : '$contents\n';
    return '$body$key: $value\n';
  }
}

/// Which file a row means and what stands in it, or why none of that can be had.
final class _Target {
  const _Target({required String this.file, required String this.contents, required this.wanted})
    : refusal = null;

  const _Target.unreachable(String this.refusal) : file = null, contents = null, wanted = null;

  final String? file;
  final String? contents;
  final String? wanted;
  final String? refusal;
}
