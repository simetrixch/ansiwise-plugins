import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';

/// Takes MicroK8s off the machine so the install that follows starts from nothing.
///
/// **This runs only when the operator asked for it.** An ordinary re-run against an installed snap
/// re-runs the network configurators in place; it does not tear the cluster down. Purging is the
/// path for a machine whose cluster is to be rebuilt, and it is destructive enough that it is asked
/// for by name rather than reached by accident.
///
/// **The group the snap created outlives the purge.** `snap remove --purge` deletes the snap and
/// leaves the `microk8s` group behind with nothing behind it. Nothing here needs it to survive — the
/// reinstall recreates the group and the user is added to it again — so it is not deleted here. A
/// teardown that claims to leave nothing behind has to delete it explicitly, and `groupdel` refuses
/// only for somebody's PRIMARY group, which a supplementary member such as the operator is not.
final class RemoveMicrok8sSnapForced extends IrreversibleStep {
  /// Purges the snap when [force] is set.
  const RemoveMicrok8sSnapForced({required this.force});

  /// Builds the step from what the program gave it.
  factory RemoveMicrok8sSnapForced.fromArguments(Arguments arguments) =>
      RemoveMicrok8sSnapForced(force: arguments.flag('force'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'force',
      kind: ArgumentKind.flag,
      describes: 'whether an installed cluster is torn down so the install starts from nothing',
      required: false,
      defaultValue: false,
    ),
  ];

  /// Whether the operator asked for the cluster to be torn down.
  final bool force;

  @override
  String get irreversibleReason =>
      'every object in the cluster and every persistent volume the snap held is deleted with it, '
      'and nothing on the machine keeps a copy — only a fresh install and a fresh deployment build '
      'them again';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!force) {
      return const CheckResult.satisfied(
        'a forced rebuild was not asked for, so an installed cluster is left where it is',
      );
    }
    if (await InstallMicrok8sSnap.trackedChannel(context) == null &&
        !await InstallMicrok8sSnap.onPath(context)) {
      return const CheckResult.satisfied(
        'no microk8s snap is installed, so there is none to purge',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    context.log.warn(
      'purging the microk8s snap: every cluster object and every volume goes with it',
    );
    final CommandResult removed = await context.shell.run(Command('snap', _argv.sublist(1)));
    if (!removed.ok) {
      throw CommandFailed(argv: _argv, exitCode: removed.exitCode, stderr: removed.stderr);
    }
  }

  static const List<String> _argv = <String>[
    'snap',
    'remove',
    InstallMicrok8sSnap.snapName,
    '--purge',
  ];
}
