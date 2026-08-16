import 'package:ansiwise_api/ansiwise_api.dart';

import 'set_process_flag.dart';

/// Replaces or appends multiple process flags in an arguments file.
///
/// Does a single restart after all flags have been written.
final class SetProcessFlags extends ReversibleStep<String?> {
  /// Instantiates a new SetProcessFlags step.
  const SetProcessFlags({
    required this.argsPath,
    required this.flags,
    required this.fileMode,
    required this.restart,
    required this.ready,
    required this.readyTimeout,
  });

  /// Builds the step from what the program gave it.
  factory SetProcessFlags.fromArguments(Arguments arguments) => SetProcessFlags(
    argsPath: arguments.text('args_path'),
    flags: arguments.textList('flags'),
    fileMode: arguments.integer('file_mode'),
    restart: arguments.textList('restart_command'),
    ready: arguments.textList('ready_command'),
    readyTimeout: Duration(seconds: arguments.integer('ready_timeout_seconds')),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'args_path',
      kind: ArgumentKind.text,
      describes: 'where the argument file stands',
    ),
    ArgumentSpec(
      name: 'flags',
      kind: ArgumentKind.textList,
      describes: 'a list of flag=value strings to set',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes: 'the permissions the argument file is written with (e.g. 384)',
    ),
    ArgumentSpec(
      name: 'restart_command',
      kind: ArgumentKind.textList,
      describes: 'the command that makes the process read its argument file again',
    ),
    ArgumentSpec(
      name: 'ready_command',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes: 'a command that succeeds once the restarted process answers again',
    ),
    ArgumentSpec(
      name: 'ready_timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 120,
      describes: 'how long to keep asking before giving up on the restarted process',
    ),
  ];

  /// The file holding the arguments.
  final String argsPath;

  /// The flags to write.
  final List<String> flags;

  /// The permissions the argument file is written with.
  final int fileMode;

  /// The command that makes the process read the argument file again.
  final List<String> restart;

  /// What succeeds once the restarted process answers again, or empty where the row said nothing.
  final List<String> ready;

  /// How long to keep asking before giving up on the restarted process.
  final Duration readyTimeout;

  String _interpolate(String text, StepContext context) {
    String filled = text;
    final RegExp slotExp = RegExp(r'<([^>]+)>');
    for (final Match match in slotExp.allMatches(text)) {
      final String slot = match.group(0)!;
      final String answerName = match.group(1)!;
      final String value = context.answers.text(answerName);
      filled = filled.replaceAll(slot, value);
    }
    return filled;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked('$argsPath is not there');
    }
    final String current = await context.files.read(argsPath);
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _interpolate(rawFlag, context));
    }

    return current == mutated
        ? CheckResult.satisfied('$argsPath carries all specified flags')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _interpolate(rawFlag, context));
    }
    return StepPlan.diff(argsPath, before: current, after: mutated);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _interpolate(rawFlag, context));
    }
    await context.files.write(argsPath, mutated, mode: fileMode);
    await SetProcessFlag.restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }

  /// The argument file as it was, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) return;
    await context.files.write(argsPath, captured, mode: fileMode);
    await SetProcessFlag.restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }
}
