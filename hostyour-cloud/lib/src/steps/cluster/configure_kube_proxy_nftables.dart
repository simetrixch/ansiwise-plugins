import 'package:ansiwise_api/ansiwise_api.dart';
import 'stamp_kube_proxy_cluster_cidr.dart';

/// Puts kube-proxy on the same packet-filtering backend the network agent uses.
///
/// **The two backends do not see each other's rules.** MicroK8s from 1.35 starts kube-proxy on the
/// older backend while the network agent writes native rules, so the two sets of rules end up in
/// different places and traffic between the host and a pod, and between two pods, is dropped by
/// whichever set the packet did not meet.
///
/// **It has to be written before anything is enabled, and that is the whole reason this step is
/// where it is.** Set now, kube-proxy paints native rules on its very first run and no rules are
/// ever written to the other backend. Set after an addon is up, the old rules already exist — and
/// nothing here removes them, because this step prevents them rather than cleaning them up.
final class ConfigureKubeProxyNftables extends ReversibleStep<String?> {
  /// Puts [proxyMode] into the kube-proxy arguments at [argsPath].
  const ConfigureKubeProxyNftables({required this.proxyMode, required this.argsPath});

  /// Builds the step from what the program gave it.
  factory ConfigureKubeProxyNftables.fromArguments(Arguments arguments) =>
      ConfigureKubeProxyNftables(
        proxyMode: arguments.text('proxy_mode'),
        argsPath: arguments.text('args_path'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'proxy_mode',
      kind: ArgumentKind.text,
      describes: 'the packet-filtering backend kube-proxy writes its rules to',
      required: false,
      defaultValue: 'nftables',
    ),
    ArgumentSpec(
      name: 'args_path',
      kind: ArgumentKind.text,
      describes: 'the file holding the arguments kube-proxy is started with',
      required: false,
      defaultValue: StampKubeProxyClusterCidr.defaultPath,
    ),
  ];

  /// The flag this step owns.
  static const String flag = '--proxy-mode';

  /// The backend kube-proxy writes its rules to.
  final String proxyMode;

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
    return current == _wanted(current)
        ? CheckResult.satisfied("kube-proxy's arguments carry $flag=$proxyMode, and only once")
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(argsPath, before: current, after: _wanted(current));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    await context.files.write(argsPath, _wanted(current), mode: StampKubeProxyClusterCidr.mode);
    await StampKubeProxyClusterCidr.restartKubelite(context);
  }

  /// kube-proxy's arguments as they were, or null when the file was not there.
  ///
  /// The step that stamps the pod range writes the same file, so the undo puts back the text it
  /// found rather than taking one flag out of whatever the file holds by then.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // The snap writes this file when it installs. There was none, so there is nothing to put back.
      return;
    }
    await context.files.write(argsPath, captured, mode: StampKubeProxyClusterCidr.mode);
    await StampKubeProxyClusterCidr.restartKubelite(context);
    // Nothing removes rules from the other backend here, and nothing has to: this step runs before
    // kube-proxy paints for the first time, so no rules were ever written there to clean up.
  }

  /// What the file has to hold: the flag once, whether it was absent or carried another value.
  String _wanted(String current) => StampKubeProxyClusterCidr.withFlag(current, '$flag=$proxyMode');

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
