import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_snap.dart';

/// Takes a snap off the machine so that what installs it next starts from nothing.
///
/// **This runs only when the operator asked for it.** An ordinary re-run against an installed snap
/// re-runs whatever configures it, in place; it does not tear down what the snap is holding. Taking
/// it away is the path for a machine that is to be rebuilt, and it is destructive enough to be asked
/// for by name rather than reached by accident — which is what the flag below is, and why it is off
/// unless a program says otherwise.
///
/// **What `--purge` adds is that nothing is kept.** `snap remove` on its own saves a snapshot of the
/// snap's data before deleting it; `--purge` is what tells snapd not to, so the machine is left with
/// no copy of anything the snap held.
///
/// **A group the snap created outlives the removal.** Removing a snap deletes the snap and its data
/// and leaves behind any system group it created, with nothing behind it. Nothing here deletes that
/// group: a machine that installs the snap again gets the group back and the accounts are put in it
/// again. A teardown that claims to leave nothing behind has to delete it explicitly, and `groupdel`
/// refuses only for somebody's PRIMARY group, which a supplementary member such as an operator's
/// account is not.
final class RemoveSnap extends IrreversibleStep {
  /// Takes [snap] off the machine when [force] is set.
  const RemoveSnap({required this.snap, required this.force});

  /// Builds the step from what the program gave it.
  factory RemoveSnap.fromArguments(Arguments arguments) =>
      RemoveSnap(snap: arguments.text('snap'), force: arguments.flag('force'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'snap',
      kind: ArgumentKind.text,
      describes: 'the snap this machine is to be left without, by the name it is published under',
    ),
    ArgumentSpec(
      name: 'force',
      kind: ArgumentKind.flag,
      describes:
          'whether a snap that is installed is taken off the machine, so what installs it next '
          'starts from nothing',
      required: false,
      defaultValue: false,
    ),
  ];

  /// The snap, by the name it is published under.
  final String snap;

  /// Whether the operator asked for the installed snap to be taken away.
  final bool force;

  @override
  String get irreversibleReason =>
      'the snap is deleted together with everything it kept in its own data directory, and --purge '
      'is what tells snapd not to save the snapshot it otherwise would — so nothing on this machine '
      'holds a copy of any of it, and only a fresh install and whatever filled that directory the '
      'first time build it again';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!force) {
      return const CheckResult.satisfied(
        'taking the snap away was not asked for, so an installed one is left where it is',
      );
    }
    if (await InstallSnap.trackedChannel(context, snap) == null &&
        !await InstallSnap.onPath(context, snap)) {
      return CheckResult.satisfied('no $snap snap is installed, so there is none to remove');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    context.log.warn('removing the $snap snap: everything it holds goes with it');
    final CommandResult removed = await context.shell.run(Command.detailed('snap', arguments: _argv.sublist(1), elevated: true));
    if (!removed.ok) {
      throw CommandFailed(argv: _argv, exitCode: removed.exitCode, stdout: removed.stdout, stderr: removed.stderr);
    }
  }

  List<String> get _argv => <String>['snap', 'remove', snap, '--purge'];
}
