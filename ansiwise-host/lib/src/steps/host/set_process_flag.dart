import 'package:ansiwise_api/ansiwise_api.dart';

/// Sets one flag in the file a process is started with, and restarts what reads it.
///
/// A service is started from a file of flags, one per line. Everything a program decides about such
/// a process — which range it treats as a network, which packet-filtering backend it paints its
/// rules into — is one line of one of those files, so one row of a program is one flag and the row
/// says which file, which flag and what it is set to.
///
/// **Which service reads the file is CONFIGURED, never known here.** A file of flags belongs to some
/// process, and which command makes that process read it again is a fact about the machine in front
/// of the run: one distribution restarts a unit by name, another restarts the whole snap the service
/// runs inside because the service is no process of its own. A step that decided this for the caller
/// would be usable on exactly one product, which is the opposite of what it is for.
///
/// **The line is compared exactly and then either replaced or appended.** A file that already carries
/// the flag with another value is edited in place; one that carries none gains the line at the end.
/// Appending unconditionally would leave two, and the process reads the last one — so a second run
/// would silently decide the question again.
///
/// **The restart is part of this and not a step of its own.** A flag written into a start-up file is
/// a change nothing is running yet: the process read its flags when it started and does not read them
/// again. So the file and the service are changed together, and only when the file really changed —
/// a second run writes nothing and restarts nothing.
///
/// **The whole file is captured, not the one line.** A file that already carried the flag with
/// another value is what makes the whole text the thing to keep: taking the line out at undo time
/// would leave the machine with no value at all where it had one before this ran. Several rows write
/// the same file, and a run unwinds from the newest step backwards, so each row lands on the text the
/// row before it left.
final class SetProcessFlag extends ReversibleStep<String?> {
  /// Sets [flag] to [value] in the argument file at [argsPath].
  const SetProcessFlag({
    required this.argsPath,
    required this.flag,
    required this.value,
    required this.fileMode,
    required this.restart,
    this.ready = const <String>[],
    this.readyTimeout = const Duration(seconds: 120),
  });

  /// The argument file belongs to whatever runs the process, and that is installed by an earlier row
  /// of the same program — so before that row has run there is no file to read and none to change.
  ///
  /// This step's own refusal already says it: the file "is not there — whatever owns this process
  /// writes it when it is installed". In a real run that is a true and useful answer, and it means
  /// the install did not happen. In the two modes that change nothing it means only that nothing has
  /// been done yet, which is the state those modes exist to be run in.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Builds the step from what the program gave it.
  factory SetProcessFlag.fromArguments(Arguments arguments) => SetProcessFlag(
    argsPath: arguments.text('args_path'),
    flag: arguments.text('flag'),
    value: arguments.optionalText('value') ?? '',
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
      describes: 'the file holding the arguments the process is started with',
    ),
    ArgumentSpec(
      name: 'flag',
      kind: ArgumentKind.text,
      describes: 'the flag this row owns, written the way the process reads it',
    ),
    ArgumentSpec(
      name: 'value',
      kind: ArgumentKind.text,
      describes: 'what that flag is set to, which may be empty where the process takes no value',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      describes:
          'the permissions the argument file is written with, as the number the machine stores — '
          '384 is the owner-only mode an argument file read by a privileged service wants',
    ),
    ArgumentSpec(
      name: 'restart_command',
      kind: ArgumentKind.textList,
      describes:
          'the command that makes the process read its argument file again, given as the program '
          'and its arguments — the file is start-up input, so nothing running takes it by itself',
    ),
    ArgumentSpec(
      name: 'ready_command',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'a command that succeeds once the restarted process answers again, given as the program '
          'and its arguments. WITHOUT IT THIS STEP RETURNS WHILE THE PROCESS IS STILL COMING BACK: '
          'a service manager reports success when it has accepted the request, not when the thing '
          'is serving, and the next row then asks a process that is down. Only the caller knows '
          'what answering means, which is why it is written here and not in the step',
    ),
    ArgumentSpec(
      name: 'ready_timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 120,
      describes:
          'how long to keep asking before giving up on the restarted process, which then fails '
          'loudly rather than leaving the rows behind it to fail one by one on a process nobody '
          'said was down',
    ),
  ];

  /// The file holding the arguments.
  final String argsPath;

  /// The flag this row owns.
  final String flag;

  /// What it is set to.
  final String value;

  /// The permissions the argument file is written with.
  final int fileMode;

  /// The command that makes the process read the argument file again.
  final List<String> restart;

  /// What succeeds once the restarted process answers again, or empty where the row said nothing.
  final List<String> ready;

  /// How long to keep asking before giving up on the restarted process.
  final Duration readyTimeout;

  /// The line this row puts in the file.
  String get line => '$flag=$value';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — whatever owns this process writes it when it is installed, so '
        'this ran before that install or against a machine it was removed from',
      );
    }
    final String current = await context.files.read(argsPath);
    return current == withFlag(current, line)
        ? CheckResult.satisfied('$argsPath carries $line, and only once')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(argsPath, before: current, after: withFlag(current, line));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    await context.files.write(argsPath, withFlag(current, line), mode: fileMode);
    await restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }

  /// The argument file as it was, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Whatever owns the process writes these files when it is installed. There was none, so
      // writing one here would leave a service started with arguments nothing on the machine put
      // there.
      return;
    }
    await context.files.write(argsPath, captured, mode: fileMode);
    await restartWith(context, restart, ready: ready, timeout: readyTimeout);
  }

  /// Whether [args] carries [line] exactly.
  ///
  /// The convergence question of a phase is often asked partly of a file and partly of the cluster.
  /// This is the file half, and it answers for nothing else.
  static bool carries(String args, String line) =>
      args.split('\n').any((String each) => each.trim() == line);

  /// [current] with [line] in it: the existing line of the same flag replaced, or the line appended.
  static String withFlag(String current, String line) {
    final String name = line.split('=').first;
    final List<String> lines = current.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].trim().startsWith('$name=')) {
        lines[i] = line;
        return lines.join('\n');
      }
    }
    final String body = current.endsWith('\n') || current.isEmpty ? current : '$current\n';
    return '$body$line\n';
  }

  /// Runs [command] so the process reads its argument file again, and waits until it answers.
  ///
  /// Shared with the steps that write one of those files for a reason of their own, so a file and
  /// the restart that makes it take effect never come apart. What to run is the caller's, because
  /// only the caller knows which process the file belongs to.
  ///
  /// **A SERVICE MANAGER REPORTS SUCCESS WHEN IT HAS ACCEPTED THE REQUEST, not when the thing is
  /// serving.** Without [ready] this returns while the process is still coming back, and the next
  /// row asks a process that is down — which answers with a failure carrying no output at all, so
  /// the row behind it reports something true about its own subject and false about the machine.
  ///
  /// That is how it was found, and the numbers are worth keeping: a restart at `23:14:08.670`, and
  /// the next row's first question at `23:14:08.904`. Two hundred and thirty-four milliseconds. Run
  /// by hand a minute later, the same question answers perfectly, which is why every check by hand
  /// said the machine was fine.
  ///
  /// Where [ready] is empty this behaves as it always did and says so in the log, because a caller
  /// that has not said what answering means cannot be given a guess.
  static Future<void> restartWith(
    StepContext context,
    List<String> command, {
    List<String> ready = const <String>[],
    Duration timeout = const Duration(seconds: 120),
    Duration interval = const Duration(seconds: 2),
  }) async {
    await context.shell.run(
      Command.detailed(command.first, arguments: command.skip(1).toList(), elevated: true),
    );

    if (ready.isEmpty) {
      context.log.warn(
        '${command.join(' ')} was asked to restart and nothing here waits for it to answer: this '
        'row states no ready_command, so a row behind it may reach the process while it is still '
        'coming back',
      );
      return;
    }

    final DateTime giveUp = context.clock.now().add(timeout);
    while (true) {
      final CommandResult answered = await context.shell.run(
        Command.observing(ready.first, ready.skip(1).toList()),
      );
      if (answered.ok) {
        context.log.debug('${ready.join(' ')} answers again');
        return;
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw StateError(
          '${ready.join(' ')} did not answer within ${timeout.inSeconds}s after '
          '${command.join(' ')} — the flag was written and the process did not come back, so '
          'nothing behind this row would be asking the machine this row left',
        );
      }
      await context.clock.sleep(interval);
    }
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
