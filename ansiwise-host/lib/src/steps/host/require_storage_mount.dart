import 'package:ansiwise_core/ansiwise_core.dart';

import 'data_disk.dart';

/// Refuses to put the cluster's volumes on a path that is not the mount it is meant to be.
///
/// The data disk is read off the mount table, and this step then asks `mountpoint` about the path
/// it read, so what the row reports as the data disk is a mount at the moment the row runs and not
/// a line somebody read a moment earlier. Everything the cluster writes through a path that is not
/// a mount lands on the boot disk, fills it, and is missing from whatever the data disk is backed up
/// by. Nothing about it looks wrong until the disk is full.
///
/// A machine with no data disk keeps the cluster's own default, which is not a failure and not a
/// warning.
final class RequireStorageMount extends ObservingStep {
  /// Refuses a machine whose data disk is not a mount.
  const RequireStorageMount({this.elevated = false});

  /// Builds the step from what the program gave it.
  factory RequireStorageMount.fromArguments(Arguments arguments) =>
      RequireStorageMount(elevated: arguments.has('elevated') && arguments.flag('elevated'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[elevationArgument];

  /// Whether the mount belongs to root, so the reading of it is elevated.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? mount = await dataDiskMount(context);
    if (mount == null) {
      return const CheckResult.satisfied(
        "this machine has no data disk, so the cluster keeps the snap's own default",
      );
    }
    // AT THIS ROW'S ELEVATION. `mountpoint` compares the path against its parent and needs to reach
    // both, and a non-zero exit is read below as "an ordinary directory rather than a mount" — so
    // asked as the operator about a path only root may enter, this step states something about the
    // machine's disks that it never measured.
    final CommandResult mounted = await context.shell.run(
      Command.observing('mountpoint', arguments: <String>['-q', mount], elevated: elevated),
    );
    if (!mounted.ok) {
      return CheckResult.blocked(
        'the mount table names $mount as the data disk, and mountpoint says it is an ordinary '
        'directory rather than a mount — everything the cluster writes through it would land on '
        "this machine's own filesystem, fill it, and be missing from whatever the data disk is "
        'backed up by',
      );
    }
    return CheckResult.satisfied('the data disk is mounted at $mount');
  }
}
