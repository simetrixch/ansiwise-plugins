import 'package:ansiwise_core/ansiwise_core.dart';

/// Records what a run wrote into the checkout it wrote it in.
///
/// **Without this a program that writes files reports success and leaves them nowhere.** Measured on
/// a machine: a run cut a branch, stamped every marker and wrote four files, ended `exit 0`, and left
/// nineteen changed paths in a working tree. Nothing said the work was unfinished, because from every
/// step's own point of view it was.
///
/// **The paths come from the row and are never "everything".** A blanket add sweeps up whatever else
/// stands in the checkout — a file an operator was editing, a leftover from a run that failed — and
/// records it as part of this installation. What is committed is what the row names.
///
/// **A path the row names and the checkout does not hold is refused before anything is staged.**
/// `git add` answers `fatal: pathspec ... did not match any files`, so such a row was already fatal
/// — but on the third path of five, with two of them already in the index, and the operator reading
/// git's message rather than this step's. The case is not hypothetical: a row went on naming a
/// directory after the tree renamed it, and nothing between the rename and the first real run said
/// so.
///
/// **And what the row names NONE of is reported rather than refused.** The other half of naming is
/// that a step writing into a directory this row does not carry produces a file the commit does not
/// record, the push does not send, and every step reports success over. So after the commit,
/// whatever the checkout still carries is written into the record — as a warning and never as a
/// failure, because refusing there would fail a run for an edit somebody made for their own
/// reasons.
///
/// **It knows git and nothing about what is in the files.** Which paths and what the message says are
/// the caller's; that a commit is `add` then `commit`, that an empty index is not an error, and that
/// an identity has to exist before either, are git's.
///
/// **Nothing here pushes.** A commit is local, and what leaves the machine is a separate act with a
/// separate credential — so a run that cannot reach the remote still records what it did.
final class GitCommit extends IrreversibleStep {
  /// Commits [paths] in [repository] with [message].
  const GitCommit({required this.repository, required this.paths, required this.message});

  /// Builds the step from what the program gave it.
  factory GitCommit.fromArguments(Arguments arguments) => GitCommit(
    repository: arguments.text('repository'),
    paths: arguments.textList('paths'),
    message: arguments.text('message'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose changes are recorded',
    ),
    ArgumentSpec(
      name: 'paths',
      kind: ArgumentKind.textList,
      describes:
          'the paths to record, relative to the checkout. Named one at a time and never "." — a '
          'blanket add records whatever else happens to stand in the tree as part of this run',
    ),
    ArgumentSpec(
      name: 'message',
      kind: ArgumentKind.text,
      describes: 'what the commit says it did',
    ),
  ];

  /// The checkout.
  final String repository;

  /// The paths recorded, relative to [repository].
  final List<String> paths;

  /// What the commit says.
  final String message;

  /// It records what earlier steps wrote, so in a mode where they did not write, there is nothing.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Nothing here can be taken back, and the reason is git's rather than this step's.
  @override
  String get irreversibleReason =>
      'a commit is a new object in the repository, and taking it back means rewriting a history '
      'that something else may already have fetched — which is a decision about the repository '
      'rather than a step this run may perform on its own';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await _isCheckout(context)) {
      return CheckResult.blocked('$repository is not a git checkout');
    }
    final List<String> absent = await _absent(context);
    if (absent.isNotEmpty) {
      return CheckResult.blocked(
        '$repository holds nothing at ${absent.join(', ')} — git tracks no such path and the work '
        'tree carries none. git add refuses a pathspec that matches nothing, so this row would '
        'stage the paths before it and then stop, leaving what the run wrote recorded nowhere',
      );
    }
    final List<String>? pending = await _pending(context);
    if (pending == null) {
      return CheckResult.blocked(
        'git could not say what differs among ${paths.join(', ')} in $repository. Read as "nothing '
        'differs" this row records nothing and answers success, and what comes after it sends a '
        'branch without the work on it',
      );
    }
    return pending.isEmpty
        ? CheckResult.satisfied('nothing among ${paths.join(', ')} differs from what is recorded')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (!await _isCheckout(context)) {
      return StepPlan.nothing('would record ${paths.join(', ')} once $repository is a checkout');
    }
    final List<String>? pending = await _pending(context);
    if (pending == null) {
      return StepPlan.nothing(
        'would record ${paths.join(', ')} once git can say what differs among them',
      );
    }
    return pending.isEmpty
        ? StepPlan.nothing('nothing among ${paths.join(', ')} differs from what is recorded')
        : StepPlan.argv(<String>['git', '-C', repository, 'commit', '-m', message, ...paths]);
  }

  @override
  Future<void> apply(StepContext context) async {
    // Staged path by path rather than in one call. The check has already refused a path the
    // checkout does not hold, so what this catches is the narrower case of one going away between
    // the two — and it catches it by name instead of losing it in a list git accepted most of.
    for (final String path in paths) {
      await _mustRun(context, <String>['-C', repository, 'add', '--', path]);
    }
    final List<String>? pending = await _pending(context);
    if (pending == null) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'status', '--porcelain', '--', ...paths],
        exitCode: 1,
        stdout: '',
        stderr:
            'git could not say what differs among ${paths.join(', ')} once they were staged, so '
            'there is nothing this step may read its own postcondition from',
      );
    }
    if (pending.isEmpty) {
      // Not a failure. A run that is repeated finds everything already recorded, and a step that
      // failed here would make a second run report a problem the machine does not have.
      return;
    }
    await _mustRun(context, <String>['-C', repository, 'commit', '-m', message]);
    await _sayWhatWasLeft(context);
  }

  /// Whether [repository] is a checkout, asked of git rather than of the file system.
  ///
  /// The sibling steps of this package ask the same way. A directory called `.git` is a checkout
  /// most of the time and a work tree of another one some of the time, and git is the thing that
  /// knows which.
  Future<bool> _isCheckout(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', '--git-dir']),
    );
    return answer.ok;
  }

  /// The paths this row names that the checkout holds nothing at.
  ///
  /// **Asked exactly the way `git add` asks it, in two questions.** A pathspec is one add accepts
  /// when the index already holds something under it, or when the work tree carries something under
  /// it that the exclude rules do not remove; it is one add refuses BY NAME when neither is true.
  /// Both are put here, before anything is staged, so a row naming a path the checkout does not
  /// hold is refused whole instead of stopping partway through the staging loop with the paths
  /// before it already in the index.
  ///
  /// The second question is put only where the first said no, so a checkout answering normally
  /// costs one command per path.
  Future<List<String>> _absent(StepContext context) async {
    final List<String> absent = <String>[];
    for (final String path in paths) {
      if (await _inTheIndex(context, path) || await _inTheWorkTree(context, path)) {
        continue;
      }
      absent.add(path);
    }
    return absent;
  }

  /// Whether the index holds anything under [path].
  Future<bool> _inTheIndex(StepContext context, String path) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'ls-files', '--error-unmatch', '--', path],
      ),
    );
    return answer.ok;
  }

  /// Whether the work tree carries anything under [path] that git would take.
  ///
  /// `--exclude-standard` is what makes this agree with add: a path the repository ignores is
  /// refused by add, and reading it as present here would send this step into a staging loop that
  /// fails on it.
  Future<bool> _inTheWorkTree(StepContext context, String path) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          repository,
          'ls-files',
          '--others',
          '--exclude-standard',
          '--',
          path,
        ],
      ),
    );
    return answer.ok && answer.trimmed.isNotEmpty;
  }

  /// The paths this row names that differ from what the repository has recorded, or null where git
  /// could not be asked.
  ///
  /// **The two answers are told apart, and that is the whole of this method.** git answers zero for
  /// a status it carried out and something above zero for one it could not — a held index lock, an
  /// unreadable object, a work tree that moved. Reading the second as "nothing differs" makes this
  /// step answer satisfied over a checkout nobody could look at: the commit is never made, the
  /// verdict is success, and the push after it sends a branch without the run's work on it. The
  /// content search of stamp_placeholder_in_tracked_files draws the same line for the same reason,
  /// and says so where it draws it.
  Future<List<String>?> _pending(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'status', '--porcelain', '--', ...paths],
      ),
    );
    if (!answer.ok) {
      return null;
    }
    return <String>[
      for (final String line in answer.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  /// Writes into the record what the checkout still carries that this row named none of.
  ///
  /// **A report and never a refusal, and the difference is the row's own choice.** What is
  /// committed is what the row names, so a file somebody was editing must not fail a run. But the
  /// cost of naming is that a step writing into a directory the row does not carry produces a file
  /// the commit does not record, the push does not send, and every step reports success over — with
  /// nothing looking. This is what looks: after the commit, whatever still differs is either
  /// somebody's own edit or a path this run wrote and this row does not name, and both are worth an
  /// operator seeing by name.
  ///
  /// What the repository ignores is not in it — git leaves an ignored path out of a plain status —
  /// which is what keeps a credential file this run wrote out of the record.
  Future<void> _sayWhatWasLeft(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'status', '--porcelain']),
    );
    if (!answer.ok) {
      context.log.warn(
        'the commit was made and git could not then be asked what else $repository carries, so '
        'nothing here says whether this run wrote outside ${paths.join(', ')}',
      );
      return;
    }
    if (answer.trimmed.isEmpty) {
      return;
    }
    context.log.warn(
      'this row names ${paths.join(', ')} and $repository still carries changes outside them:\n'
      '${answer.trimmed}\n'
      "each is either an edit of somebody's own or a path this run wrote that no row records",
    );
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
}
