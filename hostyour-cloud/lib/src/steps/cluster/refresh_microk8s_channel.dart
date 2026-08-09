import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';

/// Moves a snap that is already on the machine onto the channel this platform is pinned to.
///
/// **The channel comparison is what keeps this from failing on a machine that is already right.** A
/// plain `snap refresh` with nothing to update exits non-zero, so a step that refreshed
/// unconditionally would report a failure on every converged host. A channel SWITCH is a real
/// refresh and never reaches that exit, which is why the comparison comes first and the command
/// second.
///
/// It is written for the snap that was found installed — typically one that was switched off and
/// has just been switched back on. A fresh install lands on the pinned channel directly and never
/// reaches this step.
final class RefreshMicrok8sChannel extends IrreversibleStep {
  /// Moves the installed snap onto [channel].
  const RefreshMicrok8sChannel({required this.channel});

  /// Builds the step from what the program gave it.
  factory RefreshMicrok8sChannel.fromArguments(Arguments arguments) =>
      RefreshMicrok8sChannel(channel: arguments.text('channel'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'channel',
      kind: ArgumentKind.text,
      describes:
          'the snap channel this platform is pinned to, as platform/versions.yaml records it',
    ),
  ];

  /// The channel the snap is pinned to.
  final String channel;

  @override
  String get irreversibleReason =>
      'snapd tracks one channel and keeps no note of the one it left, so nothing on the machine can '
      'name the version to go back to — and going back across a Kubernetes minor is a downgrade the '
      'API server does not support, whatever channel is named';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? tracked = await InstallMicrok8sSnap.trackedChannel(context);
    if (tracked == null) {
      return const CheckResult.satisfied(
        'no microk8s snap is installed, so there is no channel to move',
      );
    }
    if (tracked == channel) {
      return CheckResult.satisfied('the snap already tracks $channel');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    final String? tracked = await InstallMicrok8sSnap.trackedChannel(context);
    context.log.info('moving the microk8s snap from $tracked onto $channel');
    final CommandResult refreshed = await context.shell.run(Command('snap', _argv.sublist(1)));
    if (!refreshed.ok) {
      throw CommandFailed(argv: _argv, exitCode: refreshed.exitCode, stderr: refreshed.stderr);
    }
  }

  List<String> get _argv => <String>[
    'snap',
    'refresh',
    InstallMicrok8sSnap.snapName,
    '--channel=$channel',
  ];
}
