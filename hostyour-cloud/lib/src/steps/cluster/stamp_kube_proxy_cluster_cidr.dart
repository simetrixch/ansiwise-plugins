import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';

/// Tells kube-proxy which range the pods are on.
///
/// kube-proxy translates addresses for traffic leaving the pod network, and it decides what counts
/// as leaving from this one line. A kube-proxy that still carries the old range translates the wrong
/// traffic and leaves the right traffic untranslated, which shows up as pods that can reach some
/// addresses and not others.
///
/// **The line is compared exactly and then either replaced or appended.** A file that already
/// carries `--cluster-cidr` with another value is edited in place; one that carries none gains the
/// line at the end. Appending unconditionally would leave two, and the process reads the last one —
/// so a second run would silently decide the question again.
///
/// kube-proxy has no service of its own to restart: it runs inside kubelite, which is what the
/// restart here names.
final class StampKubeProxyClusterCidr extends ReversibleStep<String?> {
  /// Puts [podCidr] into the kube-proxy arguments at [argsPath].
  const StampKubeProxyClusterCidr({required this.podCidr, required this.argsPath});

  /// Builds the step from what the program gave it.
  factory StampKubeProxyClusterCidr.fromArguments(Arguments arguments) => StampKubeProxyClusterCidr(
    podCidr: arguments.text('pod_cidr'),
    argsPath: arguments.text('args_path'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'args_path',
      kind: ArgumentKind.text,
      describes: 'the file holding the arguments kube-proxy is started with',
      required: false,
      defaultValue: defaultPath,
    ),
  ];

  /// Where the snap keeps the arguments kube-proxy is started with.
  static const String defaultPath = '${InstallMicrok8sSnap.argumentsDirectory}/kube-proxy';

  /// The flag this step owns.
  static const String flag = '--cluster-cidr';

  /// The service that has to be restarted for an argument file to be read again.
  ///
  /// kube-proxy is not a process of its own — it runs inside kubelite — so nothing about restarting
  /// "kube-proxy" would work. This is what the argument files under the snap are read by.
  static const String kubelite = 'microk8s.daemon-kubelite';

  /// `0600` — an argument file the services read as root, and nothing else has business in.
  static const int mode = 0x180;

  /// Whether [args] carries the exact line naming [podCidr].
  ///
  /// The convergence question for the whole pod-network phase is asked partly here and partly of the
  /// live address pool. This half is the file; the other half is the cluster, and neither answers
  /// for the other.
  static bool carries(String args, String podCidr) =>
      args.split('\n').any((String line) => line.trim() == '$flag=$podCidr');

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The file holding kube-proxy's arguments.
  final String argsPath;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — the snap writes it when it installs, so this ran before the '
        'install or against a machine whose snap is gone',
      );
    }
    final String current = await context.files.read(argsPath);
    if (carries(current, podCidr)) {
      return CheckResult.satisfied("kube-proxy's arguments carry $flag=$podCidr");
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(argsPath, before: current, after: withFlag(current, '$flag=$podCidr'));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    await context.files.write(argsPath, withFlag(current, '$flag=$podCidr'), mode: mode);
    await restartKubelite(context);
  }

  /// kube-proxy's arguments as they were, or null when the file was not there.
  ///
  /// A file that already carried the flag with another value is what makes the whole text the thing
  /// to keep: taking the line out at undo time would leave the machine with no range at all, where
  /// it had one before this ran.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // The snap writes this file when it installs. There was none, so there is nothing to put back.
      return;
    }
    await context.files.write(argsPath, captured, mode: mode);
    await restartKubelite(context);
  }

  /// Restarts the service the argument files are read by.
  ///
  /// Shared with the other steps that write one of those files, because the service to restart is a
  /// fact about the snap rather than about any of them.
  static Future<void> restartKubelite(StepContext context) async {
    await context.shell.run(const Command('snap', <String>['restart', kubelite]));
  }

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

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
