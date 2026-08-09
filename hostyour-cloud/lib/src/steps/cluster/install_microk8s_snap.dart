import 'package:ansiwise_api/ansiwise_api.dart';

/// Puts MicroK8s on the machine, at the channel this platform is pinned to.
///
/// **The channel is bounded from both sides and neither bound is a lag.** Below `1.35` the ingress
/// addon is nginx-ingress, and every Traefik custom resource the platform ships — `IngressRoute`,
/// `Middleware`, `ServersTransport` — has no controller behind it. Above it, `1.36` broke on the
/// pinned Ubuntu release when that release came out and had to be rolled back. Raising the pin is a
/// decision taken after a rehearsal cluster comes up clean, not something a run may do.
///
/// **A snap that is installed but switched off is refused rather than installed over.**
/// `snap disable` leaves the snap installed and only takes its entries off the path, so a check that
/// asks the path alone sees nothing while `snap install` refuses with "already installed" and the
/// whole run dies on it. That state has its own step, and this one names it instead of walking into
/// it.
final class InstallMicrok8sSnap extends IrreversibleStep {
  /// Installs the snap at [channel].
  const InstallMicrok8sSnap({required this.channel});

  /// Builds the step from what the program gave it.
  factory InstallMicrok8sSnap.fromArguments(Arguments arguments) =>
      InstallMicrok8sSnap(channel: arguments.text('channel'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'channel',
      kind: ArgumentKind.text,
      describes:
          'the snap channel this platform is pinned to, as platform/versions.yaml records it',
    ),
  ];

  /// The name the snap is published under, and the name of the command it puts on the path.
  static const String snapName = 'microk8s';

  /// The directory holding the arguments every MicroK8s service is started with.
  ///
  /// Several steps write one file in here, and the path is the same for all of them because the
  /// snap's `current` symlink is what the services read through.
  static const String argumentsDirectory = '/var/snap/microk8s/current/args';

  /// Whether the snap's command is on the path.
  ///
  /// This is the only question a bare presence test can answer, and on its own it is not enough:
  /// a disabled snap is installed and off the path at the same time. [trackedChannel] is what tells
  /// the two apart.
  static Future<bool> onPath(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      const Command.observing('command', <String>['-v', snapName]),
    );
    return answer.ok && answer.trimmed.isNotEmpty;
  }

  /// The channel the installed snap tracks, or null when no snap is installed.
  ///
  /// Read out of the fourth column of `snap list`, which snapd fills whether the snap is enabled or
  /// disabled. A non-empty answer with nothing on the path is exactly the disabled snap.
  static Future<String?> trackedChannel(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      const Command.observing('snap', <String>['list', snapName]),
    );
    if (!listed.ok) {
      return null;
    }
    for (final String line in listed.stdout.split('\n')) {
      final List<String> columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length >= 4 && columns.first == snapName) {
        return columns[3];
      }
    }
    return null;
  }

  /// The channel the snap is pinned to.
  final String channel;

  @override
  String get irreversibleReason =>
      'the machine had no Kubernetes on it, and the only way back is a purge — which deletes every '
      'cluster object and every persistent volume the snap holds, with nothing on the machine '
      'keeping a copy of either';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await onPath(context)) {
      return const CheckResult.satisfied('microk8s is installed and on the path');
    }
    final String? tracked = await trackedChannel(context);
    if (tracked != null) {
      return CheckResult.blocked(
        'a microk8s snap tracking $tracked is installed and switched off, so it is off the path '
        'while snap install refuses it as already installed — switch it back on with '
        '"snap enable microk8s"',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    context.log.info('installing the microk8s snap from $channel');
    final CommandResult installed = await context.shell.run(Command('snap', _argv.sublist(1)));
    if (!installed.ok) {
      throw CommandFailed(argv: _argv, exitCode: installed.exitCode, stderr: installed.stderr);
    }
  }

  List<String> get _argv => <String>[
    'snap',
    'install',
    snapName,
    '--classic',
    '--channel=$channel',
  ];
}
