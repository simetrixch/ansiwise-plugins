import 'package:ansiwise_api/ansiwise_api.dart';
import 'microk8s.dart';

/// Sets one flag in the file a process is started with, and restarts what reads it.
///
/// A service of the snap is started from a file of flags, one per line. Everything a program decides
/// about such a process — which range it treats as the pod network, which packet-filtering backend it
/// paints its rules into — is one line of one of those files, so one row of a program is one flag and
/// the row says which file, which flag and what it is set to.
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
  const SetProcessFlag({required this.argsPath, required this.flag, required this.value});

  /// Builds the step from what the program gave it.
  factory SetProcessFlag.fromArguments(Arguments arguments) => SetProcessFlag(
    argsPath: arguments.text('args_path'),
    flag: arguments.text('flag'),
    value: arguments.text('value'),
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
  ];

  /// The file holding the arguments.
  final String argsPath;

  /// The flag this row owns.
  final String flag;

  /// What it is set to.
  final String value;

  /// The line this row puts in the file.
  String get line => '$flag=$value';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — the snap writes it when it installs, so this ran before the '
        'install or against a machine whose snap is gone',
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
    await context.files.write(argsPath, withFlag(current, line), mode: microk8sArgumentsFileMode);
    await restartKubelite(context);
  }

  /// The argument file as it was, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // The snap writes these files when it installs. There was none, so writing one here would
      // leave a service started with arguments nothing on the machine put there.
      return;
    }
    await context.files.write(argsPath, captured, mode: microk8sArgumentsFileMode);
    await restartKubelite(context);
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

  /// Restarts the service the argument files are read by.
  ///
  /// Shared with the steps that write one of those files for a reason of their own, because the
  /// service to restart is a fact about the snap rather than about any of them. Neither kube-proxy
  /// nor the API server is a process of its own — both run inside kubelite — so nothing about
  /// restarting either by name would work.
  static Future<void> restartKubelite(StepContext context) async {
    await context.shell.run(const Command('snap', <String>['restart', microk8sKubelite]));
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
