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
    await context.files.write(
      '$repository/${target.file}',
      _withValue(target.contents!, target.wanted!),
      mode: fileMode,
    );
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

  /// What [contents] records under this key, or null where it records nothing.
  String? _valueIn(String contents) {
    for (final String line in contents.split('\n')) {
      if (line.startsWith('$key:')) {
        return line.substring(key.length + 1).trim();
      }
    }
    return null;
  }

  /// [contents] with this key holding [value]: the existing line replaced, or the line appended.
  String _withValue(String contents, String value) {
    final List<String> lines = contents.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('$key:')) {
        lines[i] = '$key: $value';
        return lines.join('\n');
      }
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
