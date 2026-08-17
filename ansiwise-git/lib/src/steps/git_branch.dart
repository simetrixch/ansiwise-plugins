import 'package:ansiwise_api/ansiwise_api.dart';

/// Cuts one branch from another, in a checkout that is standing on the one it cuts from.
///
/// **The name comes from an ANSWER, and the row says which one.** A branch that is cut per run is
/// named for something only that run knows, so the name cannot stand in a program file that ships to
/// every machine. What stands there is the NAME OF THE ANSWER — `name_answer: fqdn` — and this step
/// reads that answer out of the run. Nothing is substituted into the program file: the file carries
/// a name, and the reading happens here.
///
/// **What this refuses is git's business and nothing else.** A name git itself would reject, a
/// checkout with no branch checked out, a checkout standing somewhere other than the branch this one
/// is cut from, a name already taken, and a working tree that is not clean. Whether the name means
/// anything to the product that answered it is that product's question, asked before this row runs.
///
/// **On the branch this step is a no-op, and it never resets anything.** Running the same program
/// again on an existing branch is the normal repeat path. What this must never do is throw away an
/// existing branch to make room for a new one, so a branch that already exists is reported rather
/// than replaced.
final class GitBranch extends ReversibleStep<String?> {
  /// Cuts the branch this run names from [base], in the checkout at [repository].
  const GitBranch({required this.repository, required this.base, required this.nameAnswer});

  /// Builds the step from what the program gave it.
  factory GitBranch.fromArguments(Arguments arguments) => GitBranch(
    repository: arguments.text('repository'),
    base: arguments.text('base'),
    nameAnswer: arguments.text('name_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the branch is cut in',
    ),
    ArgumentSpec(
      name: 'base',
      kind: ArgumentKind.text,
      describes:
          'the branch this one is cut from, which is git\'s start point. It is also the only '
          'branch this step will cut from: a checkout standing anywhere else is refused rather '
          'than moved',
    ),
    // The name of the answer, never the name itself. A branch cut per run is named for something
    // only that run knows, so a program file that ships to every machine can carry the name of the
    // question and never its answer — and which question that is, is the product's to say. Naming
    // one here would make every vendor using this package carry that product's word.
    ArgumentSpec(
      name: 'name_answer',
      kind: ArgumentKind.text,
      describes:
          'the name of the answer this run reads the branch name out of — write "fqdn" here and '
          'the branch is called whatever this run answered for "fqdn"',
    ),
  ];

  /// The checkout the branch is cut in.
  final String repository;

  /// What it is cut from.
  final String base;

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

    // Git is asked whether it would take the name, rather than a second grammar being written here
    // that says what git accepts. A restatement agrees with git on the day it is written and drifts
    // from then on, and the disagreement shows up as a step that refuses a name git would have taken
    // or applies one it would not.
    final CommandResult legal = await context.shell.run(
      Command.observing('git', arguments: <String>['check-ref-format', '--branch', branch]),
    );
    if (!legal.ok) {
      return CheckResult.blocked(
        'git refuses "$branch" as a branch name, and that is what this run answered for '
        '"$nameAnswer": ${legal.stderr.trim()}',
      );
    }

    final String? head = await _head(context);
    if (head == null) {
      return CheckResult.blocked(
        'the checkout at $repository has no branch checked out, so there is nothing to cut from',
      );
    }
    if (head == branch) {
      return CheckResult.satisfied('$branch is checked out');
    }
    if (head != base) {
      return CheckResult.blocked(
        'this checkout is on "$head", and this branch is cut either from "$base" or in place on '
        '"$branch"',
      );
    }

    if (await _branchExists(context, branch)) {
      return CheckResult.blocked(
        'a branch called $branch already exists here — check it out to work on it again, or delete '
        'it if it is not the one you mean; this refuses to reset a branch somebody made',
      );
    }

    final CommandResult dirty = await _status(context);
    if (!dirty.ok) {
      return CheckResult.blocked(
        'the state of the working tree could not be read: ${dirty.stderr.trim()}',
      );
    }
    if (dirty.trimmed.isNotEmpty) {
      return CheckResult.blocked(
        'the working tree is not clean, and a branch cut from it would carry changes nobody '
        'declared: ${dirty.trimmed.split('\n').join(', ')}',
      );
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? branch = _named(context);
    // A run that answered nothing under the name this row points at is one the check above already
    // refuses. The plan says the same thing rather than throwing, so a dry run answers what it would
    // do — including "nothing, and here is why" — instead of ending in an error nobody can act on.
    if (branch == null) {
      return StepPlan.nothing(
        'this run holds no answer called "$nameAnswer", so there is no branch to cut',
      );
    }
    return StepPlan.argv(<String>['git', '-C', repository, 'checkout', '-b', branch]);
  }

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>[
      '-C',
      repository,
      'checkout',
      '-b',
      context.answers.text(nameAnswer),
    ]);
  }

  /// The branch that was checked out before this step cut its own, which is where [undo] puts the
  /// checkout back.
  ///
  /// Read before apply, because after it the checkout stands on the branch this step made and the
  /// one it came from is nowhere on the machine. It is also what says this step cut anything at all:
  /// a checkout that was already on the branch, or on none, is one an undo leaves alone.
  @override
  Future<String?> capture(StepContext context) => _head(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    final String branch = context.answers.text(nameAnswer);
    if (captured == null || captured == branch) {
      return;
    }
    // Only when this branch is still what is checked out. An undo runs while cleaning up after a
    // failure, and deleting a branch that something else moved to would take away work nobody asked
    // to lose.
    if (await _head(context) != branch) {
      return;
    }
    await _mustRun(context, <String>['-C', repository, 'checkout', captured]);
    // Nothing in this step pushes the branch, so what is deleted here exists only on this machine.
    await _mustRun(context, <String>['-C', repository, 'branch', '-D', branch]);
  }

  /// The branch name this run answered, or null when the run holds no such answer.
  String? _named(StepContext context) =>
      context.answers.has(nameAnswer) ? context.answers.text(nameAnswer) : null;

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

  /// The branch that is checked out, or null when there is none.
  ///
  /// A detached head answers with the word `HEAD`, which is not a branch and is not something to
  /// cut a branch from without saying so.
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

  Future<bool> _branchExists(StepContext context, String branch) async {
    final CommandResult answer = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          repository,
          'rev-parse',
          '--verify',
          '--quiet',
          'refs/heads/$branch',
        ],
      ),
    );
    return answer.ok;
  }

  Future<CommandResult> _status(StepContext context) => context.shell.run(
    Command.observing('git', arguments: <String>['-C', repository, 'status', '--porcelain']),
  );
}
