import 'package:ansiwise_core/ansiwise_core.dart';

/// Takes one file OFF the branch this checkout stands on.
///
/// **WHY A BRANCH EVER NEEDS THIS.** A branch is the one it was cut from plus what a program
/// WRITES into it, so every file the source branch carries stands on every branch cut from it. That is right for almost
/// everything and wrong for the few files that describe THE SOURCE BRANCH'S OWN case rather than the one
/// being generated — a file whose content is only true where it was written, and which contradicts
/// the branch it was carried onto. Until this step there was no way to take one off: every row that
/// shapes a branch writes, and a program could add to a branch but never subtract.
///
/// **IT REFUSES ON THE SOURCE BRANCH, and that is the whole safety.** The same guard the stamping row
/// carries: a checkout standing on the branch every other is cut FROM is not one of them, and a file
/// taken off it is taken off every branch cut afterwards. The branch name is read from the checkout
/// rather than believed from an argument.
///
/// **A FILE THAT IS NOT THERE IS NOT WORK.** The row is satisfied where the branch does not track
/// the path — which is what a second run finds, and what a branch cut from one that never
/// carried the file finds. Neither is an error, and neither sends a removal.
///
/// **IT DOES NOT COMMIT.** `git rm` stages the removal and stops; what a branch RECORDS is the
/// business of the row that commits, exactly as the copy beside it states for the file it writes.
final class RemoveBranchFile extends ReversibleStep<String?> {
  /// The checkout is prepared by earlier rows of the same program — cloned, fetched, put on the
  /// branch — so before those have run there may be no checkout here at all.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Removes [path] from the branch checked out at [repository].
  const RemoveBranchFile({
    required this.repository,
    required this.refuseOnBranch,
    required this.path,
  });

  /// Builds the step from what the program gave it.
  factory RemoveBranchFile.fromArguments(Arguments arguments) => RemoveBranchFile(
    repository: arguments.text('repository'),
    refuseOnBranch: arguments.text('refuse_on_branch'),
    path: arguments.text('path'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose branch the file is taken off',
    ),
    ArgumentSpec(
      name: 'refuse_on_branch',
      kind: ArgumentKind.text,
      describes:
          'the branch this row refuses to run on: a checkout standing on it is the source every '
          'installation is cut from, and a file taken off it is taken off every installation cut '
          'afterwards',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the file, as the branch tracks it — a path inside the checkout, not on the machine',
    ),
  ];

  /// The checkout whose branch the file is taken off.
  final String repository;

  /// The branch this row refuses to run on.
  final String refuseOnBranch;

  /// The file, as the branch tracks it.
  final String path;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult head = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
      ),
    );
    if (!head.ok || head.trimmed.isEmpty) {
      return CheckResult.blocked(
        'nothing in $repository answers which branch it stands on, and this row may not take a file '
        'off a checkout whose branch it does not know',
      );
    }
    if (head.trimmed == refuseOnBranch) {
      return CheckResult.blocked(
        'this checkout stands on "$refuseOnBranch", the branch every installation is cut from — a '
        'file taken off it is taken off every installation cut afterwards, so this row refuses '
        'there rather than asking',
      );
    }
    return await _tracked(context)
        ? const CheckResult.ready()
        : CheckResult.satisfied('${head.trimmed} does not carry $path');
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['git', '-C', repository, 'rm', '-f', '--', path]);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult removed = await context.shell.run(
      Command('git', <String>['-C', repository, 'rm', '-f', '--', path]),
    );
    if (!removed.ok) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'rm', '-f', '--', path],
        exitCode: removed.exitCode,
        stdout: removed.stdout,
        stderr: removed.stderr,
      );
    }
  }

  /// Whether the branch tracks [path] — asked of git rather than of the file system, because a path
  /// standing in the working tree untracked is not on the branch and is not this row's to remove.
  @override
  Future<String?> capture(StepContext context) async => await _tracked(context) ? path : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    // The committed state, back into the index AND the working tree in one command — the removal
    // staged both, so putting back only one of them would leave a checkout that says two things.
    final CommandResult back = await context.shell.run(
      Command('git', <String>['-C', repository, 'checkout', 'HEAD', '--', path]),
    );
    if (!back.ok) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'checkout', 'HEAD', '--', path],
        exitCode: back.exitCode,
        stdout: back.stdout,
        stderr: back.stderr,
      );
    }
  }

  /// Whether the branch tracks [path].
  Future<bool> _tracked(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'ls-files', '--error-unmatch', '--', path],
      ),
    );
    return listed.ok;
  }
}
