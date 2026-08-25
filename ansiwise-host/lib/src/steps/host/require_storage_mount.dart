import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses to put the cluster's volumes on a path that is not the filesystem it is meant to be on.
///
/// A machine with a separate data filesystem has it mounted at a path. If that mount is not there,
/// the path is still an ordinary directory on the machine's own filesystem — so everything written
/// through it lands on the wrong disk, fills it, and is invisible to whatever the data filesystem is
/// backed up by. Nothing about it looks wrong until the disk is full.
///
/// A machine with no separate filesystem configured keeps the cluster's own default, which is not a
/// failure and not a warning.
final class RequireStorageMount extends ObservingStep {
  /// Refuses a machine where the answered storage mount is not a mount.
  const RequireStorageMount({this.elevated = false});

  /// Builds the step from what the program gave it.
  factory RequireStorageMount.fromArguments(Arguments arguments) =>
      RequireStorageMount(elevated: arguments.has('elevated') && arguments.flag('elevated'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[elevationArgument];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Where this machine's storage is mounted, or empty when nothing is. That is a fact about one
  /// machine's disks, so it is answered rather than written into a program file.
  static const List<String> answers = <String>['storage_mount'];

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (context.answers.text('storage_mount').isEmpty) {
      return const CheckResult.satisfied(
        'this machine has no separate data filesystem, so the cluster keeps its own default',
      );
    }
    if (!await context.files.exists(context.answers.text('storage_mount'), elevated: elevated)) {
      return CheckResult.blocked(
        '${context.answers.text('storage_mount')} is not there, so nothing is mounted at it',
      );
    }
    // AT THIS ROW'S ELEVATION, like the `exists` above it on the same path. `mountpoint` compares
    // the path against its parent and needs to reach both, and a non-zero exit is read below as
    // "an ordinary directory rather than a mount" — so asked as the operator about a path only root
    // may enter, this step states something about the machine's disks that it never measured.
    final CommandResult mounted = await context.shell.run(
      Command.observing(
        'mountpoint',
        arguments: <String>['-q', context.answers.text('storage_mount')],
        elevated: elevated,
      ),
    );
    if (!mounted.ok) {
      return CheckResult.blocked(
        '${context.answers.text('storage_mount')} is an ordinary directory rather than a mount — everything the cluster writes '
        "through it would land on this machine's own filesystem, fill it, and be missing from "
        'whatever the data filesystem is backed up by',
      );
    }
    return CheckResult.satisfied(
      'the data filesystem is mounted at ${context.answers.text('storage_mount')}',
    );
  }
}
