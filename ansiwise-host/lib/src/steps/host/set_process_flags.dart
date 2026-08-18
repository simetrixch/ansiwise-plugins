import 'package:ansiwise_core/ansiwise_core.dart';

import 'fill_key_value_file.dart';
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
    this.values = const <String, KeyBinding>{},
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory SetProcessFlags.fromArguments(Arguments arguments) => SetProcessFlags(
    argsPath: arguments.text('args_path'),
    flags: arguments.textList('flags'),
    fileMode: arguments.integer('file_mode'),
    restart: arguments.textList('restart_command'),
    ready: arguments.textList('ready_command'),
    readyTimeout: Duration(seconds: arguments.integer('ready_timeout_seconds')),
    values: arguments.has('values')
        ? KeyBinding.readFrom(arguments.raw('values'))
        : const <String, KeyBinding>{},
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
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
      describes:
          'a list of flag=value strings to set. A flag may carry a marked slot wherever a value '
          'belongs that only a run holds, and `values` says which answer fills it',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.mapping,
      describes:
          'which answer fills each slot of the flags, as `slot-name: {answer: name}` and optionally '
          '`join` where the answer holds several values',
      required: false,
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
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row — an arguments file of a system service
    // usually does, a file under a checkout usually does not. Reading and writing as root does not
    // make either act anything other than a read and a write, so a dry run still refuses the write
    // and still performs the read.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so that reading and writing it need elevation. Leave '
          'it off for a path this account owns',
      required: false,
    ),
  ];

  /// The file holding the arguments.
  final String argsPath;

  /// The flags to write.
  final List<String> flags;

  /// Which answer fills each slot of those flags.
  final Map<String, KeyBinding> values;

  /// The permissions the argument file is written with.
  final int fileMode;

  /// The command that makes the process read the argument file again.
  final List<String> restart;

  /// What succeeds once the restarted process answers again, or empty where the row said nothing.
  final List<String> ready;

  /// How long to keep asking before giving up on the restarted process.
  final Duration readyTimeout;

  /// [text] with the slot named by each binding holding that binding's value.
  ///
  /// The FRAMEWORK's grammar and no second one. What stood here was a private pattern with its own
  /// rules — it took any characters between angle brackets, looked the name up verbatim, and filled
  /// nothing where the answer was absent without saying so. That made the same text mean one thing
  /// in a template and another in a flag, which is exactly what one notation exists to prevent.
  ///
  /// A slot nothing filled is REFUSED rather than written out: `--oidc-issuer-url=<books-cluster>`
  /// reaching an argument file is a flag the process reads as that literal text.
  String _filled(String text, StepContext context) {
    final String written = filledSlots(text, <String, String>{
      for (final MapEntry<String, KeyBinding> each in values.entries)
        if (each.value.valueIn(context.answers) case final String value) each.key: value,
    });
    if (leftoverSlotIn(written) case final String left) {
      throw TemplateRefused(
        '$left in "$text" is filled by nothing: `values` says which answer fills each slot, and a '
        'flag still carrying one would be read by the process as that literal text',
      );
    }
    return written;
  }

  /// Whether the file belongs to root, so every read and write of it is elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(argsPath, elevated: elevated)) {
      return CheckResult.blocked('$argsPath is not there');
    }
    final String current = await context.files.read(argsPath, elevated: elevated);
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _filled(rawFlag, context));
    }

    return current == mutated
        ? CheckResult.satisfied('$argsPath carries all specified flags')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await context.files.exists(argsPath, elevated: elevated)
        ? await context.files.read(argsPath, elevated: elevated)
        : '';
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _filled(rawFlag, context));
    }
    return StepPlan.diff(argsPath, before: current, after: mutated);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await context.files.exists(argsPath, elevated: elevated)
        ? await context.files.read(argsPath, elevated: elevated)
        : '';
    String mutated = current;
    for (final String rawFlag in flags) {
      mutated = SetProcessFlag.withFlag(mutated, _filled(rawFlag, context));
    }
    await context.files.write(argsPath, mutated, mode: fileMode, elevated: elevated);
    await SetProcessFlag.restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }

  /// The argument file as it was, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath, elevated: elevated)
      ? context.files.read(argsPath, elevated: elevated)
      : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) return;
    await context.files.write(argsPath, captured, mode: fileMode, elevated: elevated);
    await SetProcessFlag.restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }
}
