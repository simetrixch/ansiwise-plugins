import 'package:ansiwise_core/ansiwise_core.dart';

/// Brings the branch that is checked out up to a stated commit, by merging that commit into it.
///
/// **What this is for.** A branch generated from a source branch does not follow it: when the source
/// moves, the generated branch stays where it was cut, and bringing it forward is a deliberate act
/// against a deliberately chosen commit — a tag somebody released, never whatever happens to be the
/// tip today. The commit is therefore an ARGUMENT the row states, and a row usually states it as
/// `{measured: value}`: the commit is recorded somewhere on the branch itself, an earlier row reads
/// it out, and no person re-types it. Where a person names the state instead, the row names
/// `ref_answer` — the answer this run reads the commit out of — and writes no `ref` at all.
///
/// **A merge and not a reset, because the branch owns content the source never carried.** A
/// generated branch holds two kinds of bytes: what came from the source, and what was written onto
/// the branch afterwards — its own settings, its own records. A reset to the commit would throw the
/// second kind away wholesale; a merge keeps everything only the branch has, brings in everything
/// only the commit has, and leaves exactly the overlaps as conflicts.
///
/// **EVERY CONFLICT STOPS THE MERGE, aborted and named.** A conflict means the branch and the
/// commit both decided something about the same bytes, and only a person can say which decision
/// stands. A step that guessed would guess exactly where guessing destroys somebody's record. The
/// refusal carries every conflicted path at once, so one run tells an operator everything they have
/// to settle.
///
/// **Already-merged is the satisfied state, not an error.** A branch that already carries the commit
/// among its ancestors has nothing to take, so a second run finds nothing to do — which is what
/// makes the operation repeatable on a branch that failed further down the program.
final class GitMergeRef extends ReversibleStep<String?> {
  /// Merges [ref] — or the value the run answers under [refAnswer] — into the branch named by
  /// [branchAnswer], in the checkout at [repository].
  const GitMergeRef({
    required this.repository,
    required this.branchAnswer,
    required this.ref,
    this.refAnswer,
  });

  /// Builds the step from what the program gave it.
  ///
  /// [ref] is read as absent-or-stated because a row usually takes it from a measurement, and
  /// everything that examines a program before it runs has to build the step while that value does
  /// not exist yet.
  factory GitMergeRef.fromArguments(Arguments arguments) => GitMergeRef(
    repository: arguments.text('repository'),
    branchAnswer: arguments.text('branch_answer'),
    ref: arguments.optionalText('ref') ?? '',
    refAnswer: arguments.optionalText('ref_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the merge happens in',
    ),
    // The name of the answer, never the name itself: the branch being brought forward is named for
    // something only the run knows, so the row carries the name of the question — the same shape
    // the row that cuts a branch uses.
    ArgumentSpec(
      name: 'branch_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer this run reads the branch name out of — the merge refuses to run '
          'while any other branch is checked out, rather than moving the checkout itself',
    ),
    ArgumentSpec(
      name: 'ref',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the commit the branch is brought up to — a tag, a branch, or anything git resolves to '
          'one. A row usually takes it from a measurement, because the commit is recorded on the '
          'branch itself and no person should re-type it',
    ),
    ArgumentSpec(
      name: 'ref_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer this run reads that commit out of, where a person names the '
          'state the branch is brought to — a row writes "ref" or this, never both',
    ),
  ];

  /// The checkout the merge happens in.
  final String repository;

  /// The name of the answer the branch name is read out of.
  final String branchAnswer;

  /// The commit the branch is brought up to, or empty while nothing has measured it yet.
  final String ref;

  /// The name of the answer the commit is read out of, or null where the row writes it as [ref].
  final String? refAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? branch = context.answers.optionalText(branchAnswer);
    if (branch == null || branch.isEmpty) {
      return CheckResult.blocked(
        'this run holds no answer called "$branchAnswer", and that is where this row says the name '
        'of the branch being brought forward comes from',
      );
    }
    if (_unreadable(context) case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final String? head = await _head(context);
    if (head == null) {
      return CheckResult.blocked(
        'the checkout at $repository has no branch checked out, so there is nothing to bring '
        'forward',
      );
    }
    if (head != branch) {
      return CheckResult.blocked(
        'this checkout is on "$head", and the branch being brought to ${_refOf(context)} is '
        '"$branch" — check that branch out first; this step refuses to move a checkout somebody '
        'else is standing on',
      );
    }

    if (await _inProgress(context)) {
      return CheckResult.blocked(
        'a merge is already in progress in $repository — finish or abort it first, because a '
        'second one started over it would act on a tree that is half of two things',
      );
    }

    final CommandResult resolved = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          repository,
          'rev-parse',
          '--verify',
          '--quiet',
          '${_refOf(context)}^{commit}',
        ],
      ),
    );
    if (!resolved.ok) {
      return CheckResult.blocked(
        'nothing in $repository resolves "${_refOf(context)}" to a commit — fetch it first, '
        'because a merge against a name the checkout does not hold has nothing to merge',
      );
    }

    final CommandResult dirty = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'status', '--porcelain']),
    );
    if (!dirty.ok) {
      return CheckResult.blocked(
        'the state of the working tree could not be read: ${dirty.stderr.trim()}',
      );
    }
    if (dirty.trimmed.isNotEmpty) {
      return CheckResult.blocked(
        'the working tree is not clean, and a merge over it would fold changes nobody declared '
        'into the merge commit: ${dirty.trimmed.split('\n').join(', ')}',
      );
    }

    final CommandResult carried = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          repository,
          'merge-base',
          '--is-ancestor',
          _refOf(context),
          'HEAD',
        ],
      ),
    );
    if (carried.ok) {
      return CheckResult.satisfied(
        '$branch already carries ${_refOf(context)} among its ancestors',
      );
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.argv(<String>['git', '-C', repository, 'merge', '--no-edit', _refOf(context)]);
  }

  @override
  Future<void> apply(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      throw StateError(refusal);
    }
    final CommandResult merged = await context.shell.run(
      Command('git', <String>['-C', repository, 'merge', '--no-edit', _refOf(context)]),
    );
    if (merged.ok) {
      return;
    }

    // The merge stopped. Everything it could not resolve is read off the index rather than parsed
    // out of the message, because the message is written for a person and changes between versions.
    final List<String> conflicted = await _conflictedPaths(context);
    if (conflicted.isEmpty) {
      // No conflicts and still not ok is a failure of the merge itself — a broken tree, a refused
      // strategy — and the honest report is the command's own words.
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'merge', '--no-edit', _refOf(context)],
        exitCode: merged.exitCode,
        stdout: merged.stdout,
        stderr: merged.stderr,
      );
    }

    // Aborted BEFORE refusing, so the branch is left standing where it stood rather than in the
    // middle of a merge nobody finished. The refusal names every path at once: an operator
    // resolving one per run is an operator running this as many times as there are paths.
    await _mustRun(context, <String>['-C', repository, 'merge', '--abort']);
    throw StateError(
      'the merge of ${_refOf(context)} stopped on ${conflicted.join(', ')} — the branch and the '
      'incoming commit both decided something there, so only a person can say which decision '
      'stands. The merge was aborted; nothing changed.',
    );
  }

  /// The commit the branch stood on before the merge, which is where [undo] puts it back.
  @override
  Future<String?> capture(StepContext context) async {
    final CommandResult head = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', 'HEAD']),
    );
    return head.ok && head.trimmed.isNotEmpty ? head.trimmed : null;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    // A merge stopped halfway is taken back as a whole, whatever it managed to stage.
    if (await _inProgress(context)) {
      await _mustRun(context, <String>['-C', repository, 'merge', '--abort']);
    }
    if (captured == null) {
      return;
    }
    final CommandResult head = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', 'HEAD']),
    );
    if (!head.ok || head.trimmed == captured) {
      return;
    }
    // Only the merge commit this step made is stepped back over: its first parent is the commit
    // that was captured. A head anywhere else was moved by something after this step, and resetting
    // over it would take away work nobody asked to lose.
    final CommandResult parent = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', 'HEAD^1']),
    );
    if (!parent.ok || parent.trimmed != captured) {
      return;
    }
    await _mustRun(context, <String>['-C', repository, 'reset', '--hard', captured]);
  }

  /// The commit the branch is brought up to, or the empty text while nothing names one.
  String _refOf(StepContext context) {
    if (ref.isNotEmpty) {
      return ref;
    }
    if (refAnswer case final String named) {
      return context.answers.has(named) ? context.answers.text(named).trim() : '';
    }
    return '';
  }

  /// Why this row cannot be read at all, or null where it can.
  String? _unreadable(StepContext context) {
    if (ref.isNotEmpty && refAnswer != null) {
      return 'this row states "ref" AND names "ref_answer", and one row brings the branch to one '
          'commit — write the commit, or name the answer holding it, never both';
    }
    if (ref.isEmpty && refAnswer == null) {
      return 'no commit to merge was given — the row states "ref", usually as {measured: value} '
          'from the row that reads where this branch is recorded to stand, or names "ref_answer" '
          'where a person answers the state the branch is brought to';
    }
    if (refAnswer != null && _refOf(context).isEmpty) {
      return 'this run holds no answer called "$refAnswer", and that is where this row says the '
          'commit the branch is brought to comes from';
    }
    return null;
  }

  /// Whether a merge is standing unfinished in the checkout.
  Future<bool> _inProgress(StepContext context) async {
    final CommandResult merging = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--verify', '--quiet', 'MERGE_HEAD'],
      ),
    );
    return merging.ok;
  }

  /// Every path the stopped merge could not resolve.
  Future<List<String>> _conflictedPaths(StepContext context) async {
    final CommandResult unmerged = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'diff', '--name-only', '--diff-filter=U'],
      ),
    );
    if (!unmerged.ok) {
      return const <String>[];
    }
    return unmerged.trimmed.isEmpty
        ? const <String>[]
        : unmerged.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command('git', argv));
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: answer.exitCode,
        stdout: '',
        stderr: answer.stderr,
      );
    }
  }

  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
      ),
    );
    if (!answer.ok || answer.trimmed.isEmpty || answer.trimmed == 'HEAD') {
      return null;
    }
    return answer.trimmed;
  }
}
