import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';

/// Switches a snap that is installed but turned off back on.
///
/// **A disabled snap is invisible to the path and visible to snapd, and that pair is the whole
/// incident.** `snap disable microk8s` leaves the snap installed and only removes its entries from
/// `/snap/bin`, so a presence test built on the path finds nothing and concludes the machine is
/// clean — while `snap install` refuses the very same snap as already installed and the run dies
/// there. Reading the tracked channel out of `snap list` is what tells the two states apart, and
/// switching the snap back on is what this step does about it.
///
/// It is deliberately not an install. The snap on the machine carries its data directory, its
/// certificates and its cluster; installing over it would be a different and much larger act than
/// the one the machine needs.
final class EnableDisabledMicrok8sSnap extends ReversibleStep {
  /// Switches the installed snap back on.
  const EnableDisabledMicrok8sSnap();

  /// Builds the step from what the program gave it.
  factory EnableDisabledMicrok8sSnap.fromArguments(Arguments arguments) =>
      const EnableDisabledMicrok8sSnap();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await InstallMicrok8sSnap.onPath(context)) {
      return const CheckResult.satisfied('microk8s is on the path, so the snap is switched on');
    }
    final String? tracked = await InstallMicrok8sSnap.trackedChannel(context);
    if (tracked == null) {
      return const CheckResult.satisfied(
        'no microk8s snap is installed, so there is none to switch on',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(_enable);

  @override
  Future<void> apply(StepContext context) async {
    context.log.info('a microk8s snap is installed and switched off — switching it back on');
    final CommandResult enabled = await context.shell.run(Command('snap', _enable.sublist(1)));
    if (!enabled.ok) {
      throw CommandFailed(argv: _enable, exitCode: enabled.exitCode, stderr: enabled.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    // Only when the snap is on the path, which is the state this step produced. An undo runs while
    // cleaning up after a failure, and switching off a snap that something else installed in the
    // meantime would take away a cluster nobody asked to lose.
    if (!await InstallMicrok8sSnap.onPath(context)) {
      return;
    }
    await context.shell.run(Command('snap', _disable.sublist(1)));
  }

  static const List<String> _enable = <String>['snap', 'enable', InstallMicrok8sSnap.snapName];
  static const List<String> _disable = <String>['snap', 'disable', InstallMicrok8sSnap.snapName];
}
