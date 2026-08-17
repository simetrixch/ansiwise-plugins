import 'package:ansiwise_api/ansiwise_api.dart';

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
    final List<String> pending = await _pending(context);
    return pending.isEmpty
        ? CheckResult.satisfied('nothing among ${paths.join(', ')} differs from what is recorded')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (!await _isCheckout(context)) {
      return StepPlan.nothing('would record ${paths.join(', ')} once $repository is a checkout');
    }
    final List<String> pending = await _pending(context);
    return pending.isEmpty
        ? StepPlan.nothing('nothing among ${paths.join(', ')} differs from what is recorded')
        : StepPlan.argv(<String>['git', '-C', repository, 'commit', '-m', message, ...paths]);
  }

  @override
  Future<void> apply(StepContext context) async {
    // Staged path by path rather than in one call, so a path the row names and the tree does not
    // hold is refused by name instead of being lost in a list git accepted most of.
    for (final String path in paths) {
      await _mustRun(context, <String>['-C', repository, 'add', '--', path]);
    }
    if ((await _pending(context)).isEmpty) {
      // Not a failure. A run that is repeated finds everything already recorded, and a step that
      // failed here would make a second run report a problem the machine does not have.
      return;
    }
    await _mustRun(context, <String>['-C', repository, 'commit', '-m', message]);
  }

  /// Whether [repository] is a checkout, asked of git rather than of the file system.
  ///
  /// The sibling steps of this package ask the same way. A directory called `.git` is a checkout
  /// most of the time and a work tree of another one some of the time, and git is the thing that
  /// knows which.
  Future<bool> _isCheckout(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--git-dir']),
    );
    return answer.ok;
  }

  /// The paths this row names that differ from what the repository has recorded.
  Future<List<String>> _pending(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'status', '--porcelain', '--', ...paths]),
    );
    if (!answer.ok) {
      return const <String>[];
    }
    return <String>[
      for (final String line in answer.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
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
