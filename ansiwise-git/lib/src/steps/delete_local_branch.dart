import 'package:ansiwise_core/ansiwise_core.dart';

/// Deletes one branch in one checkout, and never the branch the remote publishes.
///
/// **WHAT IT IS FOR.** A branch a run left half-cut is regenerated rather than resumed: the files it
/// carries are stamped from what the program says today, and a branch standing at yesterday's
/// attempt would be stamped on top of a state nobody can describe. Deleting the local name is how
/// the next run starts from the branch it is cut from again.
///
/// **THE LOCAL NAME ONLY, AND THAT IS THE WHOLE OF THE NAME.** `git branch -D` removes a name in one
/// checkout. What the remote publishes is untouched, and this step never sends anything: a published
/// branch is something other machines have already resolved, and taking it away is not a thing a
/// deployment does on its way past.
///
/// **THE NAME COMES FROM AN ANSWER, and the row says which one.** The same argument `git_branch`
/// declares, so one program names one answer in the row that cuts the branch and in the row that
/// deletes it.
///
/// **IT CAN BE TAKEN BACK, and what that means is exact.** The capture is the commit the branch
/// stood on, and the undo cuts the name again at that commit. What is not put back is the branch's
/// own reflog, which is this checkout's record of where the name has been — the name and the commit
/// it points at are.
final class DeleteLocalBranch extends ReversibleStep<String?> {
  /// The checkout is placed by an earlier row of the same program, so before that has run there may
  /// be no checkout here at all.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Deletes the branch this run names, in the checkout at [repository].
  const DeleteLocalBranch({required this.repository, required this.nameAnswer});

  /// Builds the step from what the program gave it.
  factory DeleteLocalBranch.fromArguments(Arguments arguments) => DeleteLocalBranch(
    repository: arguments.text('repository'),
    nameAnswer: arguments.text('name_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the branch is deleted in',
    ),
    ArgumentSpec(
      name: 'name_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer this run reads the branch name out of — write "fqdn" here and '
          'the branch called whatever this run answered for "fqdn" is the one deleted',
    ),
  ];

  /// The checkout the branch is deleted in.
  final String repository;

  /// The name of the answer the branch name is read out of.
  final String nameAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? branch = _named(context);
    if (branch == null) {
      return CheckResult.blocked(
        'this run holds no answer called "$nameAnswer", and that is where this row says the name '
        'of the branch comes from',
      );
    }

    final ({String? commit, String? refusal}) standing = await _tipOf(context, branch);
    if (standing.refusal case final String refusal) {
      return CheckResult.blocked(
        'whether $repository carries a branch called "$branch" could not be read, so this row can '
        'say neither that there is one to delete nor that there is not: $refusal',
      );
    }
    if (standing.commit == null) {
      return CheckResult.satisfied('$repository carries no branch called $branch');
    }

    final CommandResult head = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    if (head.trimmed == branch) {
      return CheckResult.blocked(
        'this checkout stands on "$branch", and git deletes no branch that is checked out — the '
        'row that stands it on the branch this one is cut from has still to run',
      );
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? branch = _named(context);
    if (branch == null) {
      return StepPlan.nothing(
        'this run holds no answer called "$nameAnswer", so there is no branch to delete',
      );
    }
    return StepPlan.argv(<String>['git', '-C', repository, 'branch', '-D', branch]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String branch = context.answers.text(nameAnswer);
    final List<String> argv = <String>['-C', repository, 'branch', '-D', branch];
    final CommandResult deleted = await context.shell.run(Command('git', argv));
    if (!deleted.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: deleted.exitCode,
        stdout: deleted.stdout,
        stderr: deleted.stderr,
      );
    }
  }

  /// The commit the branch stood on before this ran, which is what [undo] cuts it again at.
  ///
  /// Null where there was no such branch: nothing was taken away, so there is nothing to put back.
  @override
  Future<String?> capture(StepContext context) async {
    final String? branch = _named(context);
    if (branch == null) {
      return null;
    }
    final ({String? commit, String? refusal}) standing = await _tipOf(context, branch);
    if (standing.refusal case final String refusal) {
      // A capture answers the undo an instruction and there is no third value meaning "nobody read
      // this". So it answers the half that leaves the machine as it stands, and says here that it
      // is not a measurement: if this row did delete a branch after all, the undo will not put it
      // back, and the commit it stood on is in this checkout's reflog and nowhere this step reads.
      context.log.warn(
        'the commit "$branch" stood on in $repository could not be read, so an undo will put no '
        'branch back rather than cut one at a commit nobody measured: $refusal',
      );
      return null;
    }
    return standing.commit;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    final String branch = context.answers.text(nameAnswer);
    final List<String> argv = <String>['-C', repository, 'branch', branch, captured];
    final CommandResult back = await context.shell.run(Command('git', argv));
    if (!back.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: back.exitCode,
        stdout: back.stdout,
        stderr: back.stderr,
      );
    }
  }

  /// The branch name this run answered, or null when the run holds no such answer.
  String? _named(StepContext context) =>
      context.answers.has(nameAnswer) ? context.answers.text(nameAnswer) : null;

  /// The commit [branch] stands on here, null where this checkout carries no such branch, or why
  /// neither could be read.
  ///
  /// **EXIT ONE IS THE ANSWER AND ANYTHING ELSE IS NOT.** `rev-parse --verify --quiet` exits one for
  /// a ref that resolves to nothing, which is git saying there is no such branch. Every other
  /// non-zero exit is git not having answered the question at all — no repository at that path, a
  /// checkout it refuses to read — and folded into the same null it would make this row report a
  /// branch already gone over a checkout nobody could read.
  Future<({String? commit, String? refusal})> _tipOf(StepContext context, String branch) async {
    final CommandResult resolved = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--verify',
      '--quiet',
      'refs/heads/$branch',
    ]);
    if (resolved.exitCode == 1) {
      return (commit: null, refusal: null);
    }
    if (resolved.exitCode != 0 || resolved.trimmed.isEmpty) {
      return (
        commit: null,
        refusal:
            'git exited ${resolved.exitCode}'
            '${resolved.stderr.trim().isEmpty ? ' and wrote nothing' : ': ${resolved.stderr.trim()}'}',
      );
    }
    return (commit: resolved.trimmed, refusal: null);
  }

  Future<CommandResult> _observe(StepContext context, List<String> argv) =>
      context.shell.run(Command.observing('git', arguments: argv));
}
