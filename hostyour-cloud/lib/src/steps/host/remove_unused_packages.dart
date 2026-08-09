import 'package:ansiwise_api/ansiwise_api.dart';

/// Removes the packages nothing on the machine asked for any more.
///
/// The postcondition is that apt has nothing left to remove, which it will say when asked. That is
/// what makes this idempotent: a second run finds nothing and does nothing, rather than running the
/// command again and reporting that it worked.
final class RemoveUnusedPackages extends IrreversibleStep {
  /// Removes what nothing depends on.
  const RemoveUnusedPackages();

  /// Builds the step from what the program gave it.
  factory RemoveUnusedPackages.fromArguments(Arguments arguments) => const RemoveUnusedPackages();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  @override
  String get irreversibleReason =>
      'the packages are gone and nothing recorded which of them this removed, so putting them back '
      'would mean guessing';

  @override
  Future<CheckResult> check(StepContext context) async {
    final int count = await _wouldRemove(context);
    if (count == 0) {
      return const CheckResult.satisfied('nothing on this machine is unused');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final int count = await _wouldRemove(context);
    // The count goes into the record as this step's own note rather than into the plan. A plan says
    // what would run; how much it would touch is what the operator wants beside it, and a note is
    // already attributed to this step and already in the right place in the record.
    context.log.info(
      count == 1 ? '1 package would be removed' : '$count packages would be removed',
    );
    return const StepPlan.argv(<String>['apt-get', 'autoremove', '--yes'], serverVerified: true);
  }

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult removed = await context.shell.run(
      const Command.detailed(
        'apt-get',
        arguments: <String>['autoremove', '--yes'],
        environment: <String, String>{'DEBIAN_FRONTEND': 'noninteractive'},
      ),
    );
    if (!removed.ok) {
      throw CommandFailed(
        argv: const <String>['apt-get', 'autoremove', '--yes'],
        exitCode: removed.exitCode,
        stderr: removed.stderr,
      );
    }
  }

  /// How many packages apt says it would remove.
  ///
  /// Asked with `--dry-run`, so the plan a dry run shows is what apt answered rather than what we
  /// predicted. The line to read is the one that begins `Remv `.
  Future<int> _wouldRemove(StepContext context) async {
    final CommandResult asked = await context.shell.run(
      const Command.observing('apt-get', <String>['--dry-run', 'autoremove']),
    );
    if (!asked.ok) {
      return 0;
    }
    return asked.stdout.split('\n').where((String line) => line.startsWith('Remv ')).length;
  }
}
