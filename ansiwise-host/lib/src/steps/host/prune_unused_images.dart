import 'package:ansiwise_core/ansiwise_core.dart';

import 'on_the_path.dart';
import 'require_free_disk.dart';

/// Removes the container images no container uses, where a disk is below its floor.
///
/// A cluster keeps every image it ever pulled until its runtime's own collection reaches its
/// threshold, and that threshold can sit above the room an installation demands. A machine that
/// ran many releases then refuses the free-disk check on its next deploy, with every byte of the
/// shortfall held by images nothing runs.
///
/// **Only below the floor.** At or above [freeKibibytes] on [path] the step is satisfied and runs
/// nothing, so a healthy machine keeps its images and pulls nothing again. The disk is read the way
/// require_free_disk reads it, so the two rows agree about what "below" means.
///
/// **Only what no container uses.** The prune command is the row's, and it removes the images that
/// no container references, running or stopped. A pod that needs a pruned image again pulls it from
/// its registry; that is the cost, and why the step is irreversible.
///
/// **Nothing to prune before the runtime exists.** On a machine where the prune command is not on
/// the path, nothing was pulled yet, and the step is satisfied rather than failed.
final class PruneUnusedImages extends IrreversibleStep {
  /// Prunes with [pruneCommand] while [path] has less than [freeKibibytes] free.
  const PruneUnusedImages({
    required this.path,
    required this.freeKibibytes,
    required this.pruneCommand,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory PruneUnusedImages.fromArguments(Arguments arguments) => PruneUnusedImages(
    path: arguments.text('path'),
    freeKibibytes: arguments.integer('free_kibibytes'),
    pruneCommand: arguments.textList('prune_command'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the directory whose file system the images fill',
      defaultValue: '/',
    ),
    // No default: it is the floor of the free-disk check this row stands before.
    ArgumentSpec(
      name: 'free_kibibytes',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 65536,
        most: 1099511627776,
        because: 'the same band as require_free_disk, whose floor this is',
      ),
      describes:
          'the free space below which unused images are removed, in KiB as df -Pk reports it',
    ),
    ArgumentSpec(
      name: 'prune_command',
      kind: ArgumentKind.textList,
      describes: 'the command that removes every image no container uses',
    ),
    elevationArgument,
  ];

  /// The directory whose file system is measured.
  final String path;

  /// The floor, in kibibytes.
  final int freeKibibytes;

  /// The command that removes the unused images.
  final List<String> pruneCommand;

  /// Whether the runtime refuses the account the run started as.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'the unused images are deleted; a pod that needs one again pulls it from its registry';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult measured = await context.shell.run(
      Command.observing('df', arguments: <String>['-Pk', path], elevated: elevated),
    );
    if (!measured.ok) {
      return CheckResult.blocked('df could not measure $path: ${measured.stderr.trim()}');
    }
    final int? available = RequireFreeDisk.availableKibibytesIn(measured.stdout);
    if (available == null) {
      return CheckResult.blocked('df answered something $path cannot be read out of');
    }
    if (available >= freeKibibytes) {
      return CheckResult.satisfied(
        '$path has $available KiB free, at or above $freeKibibytes KiB, so no image is pruned',
      );
    }
    if (!foundOnThePath(
      await context.shell.run(onThePath(pruneCommand.first, elevated: elevated)),
    )) {
      return CheckResult.satisfied(
        '${pruneCommand.first} is not on the path, so no image was pulled here yet',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    context.log.info(
      'every image no container uses is removed, so a workload without a running container (a job '
      'between its runs, a deployment scaled to zero) pulls its image again on its next start, '
      'and fails to start while its registry cannot be reached',
    );
    return StepPlan.argv(pruneCommand);
  }

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult pruned = await context.shell.run(
      Command.detailed(pruneCommand.first, arguments: pruneCommand.sublist(1), elevated: elevated),
    );
    if (!pruned.ok) {
      throw CommandFailed(
        argv: pruneCommand,
        exitCode: pruned.exitCode,
        stdout: '',
        stderr: pruned.stderr,
      );
    }
  }
}
