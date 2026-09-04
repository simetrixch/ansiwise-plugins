import 'package:ansiwise_core/ansiwise_core.dart';

/// Stands a checkout on a branch the remote already publishes, at the tip the remote publishes.
///
/// **THE OTHER HALF OF CUTTING A BRANCH.** `git_branch` cuts a name that does not exist yet and
/// refuses one that does, deliberately: throwing away an existing branch to make room for a new one
/// is the failure that refusal exists to stop. This is the case it refuses. A branch this machine
/// published on an earlier run has to be GROWN from, not cut beside: a branch cut fresh every time
/// shares no history with what stands on the remote, and the push at the end of it is refused as a
/// non-fast-forward.
///
/// **THE NAME COMES FROM AN ANSWER, and the row says which one.** Deliberately the same argument as
/// `git_branch` writes, so one program names one answer in the row that cuts the branch and in the
/// row that stands on it.
///
/// **IT FETCHES THE ONE BRANCH IT PLACES.** A checkout resolves `<remote>/<branch>` to whatever it
/// last saw, and to nothing at all for a branch it has never fetched — so placing the local branch
/// on that name without asking the remote first would put the checkout on a tree the remote no
/// longer publishes, or fail on a name this checkout has never heard of. Bringing the branch is part
/// of standing on it rather than a row somebody has to remember, for the reason `git_fetch` cannot
/// serve here: its `branch` is text, and the branch this row places is named by an answer.
///
/// **A WORKING TREE THAT IS NOT CLEAN IS REFUSED.** The placement is `checkout -B`, and where the
/// uncommitted change does not collide git carries it silently onto the branch being placed. What
/// lands in the next commit is then something nobody declared, so this row stops and names the paths
/// instead.
final class GitCheckoutBranch extends IrreversibleStep {
  /// The checkout is placed by an earlier row of the same program, so before that has run there may
  /// be no checkout here at all.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Stands the checkout at [repository] on the branch this run names, as [remote] publishes it.
  const GitCheckoutBranch({
    required this.repository,
    required this.remote,
    required this.nameAnswer,
  });

  /// Builds the step from what the program gave it.
  factory GitCheckoutBranch.fromArguments(Arguments arguments) => GitCheckoutBranch(
    repository: arguments.text('repository'),
    remote: arguments.optionalText('remote') ?? 'origin',
    nameAnswer: arguments.text('name_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout that is stood on the branch',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: 'origin',
      describes:
          'the remote the branch is brought from and whose tip the local branch is placed on',
    ),
    // The name of the answer, never the name itself, and the same argument `git_branch` declares. A
    // branch named per run is named for something only that run knows, so a program file that ships
    // to every machine carries the name of the question and never its answer.
    ArgumentSpec(
      name: 'name_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer this run reads the branch name out of — write "fqdn" here and '
          'the checkout is stood on whatever this run answered for "fqdn"',
    ),
  ];

  /// The checkout that is stood on the branch.
  final String repository;

  /// The remote it is brought from.
  final String remote;

  /// The name of the answer the branch name is read out of.
  final String nameAnswer;

  @override
  String get irreversibleReason =>
      'the branch this row places is moved onto the tip $remote publishes, and where a local branch '
      'of that name already stood, the commit it stood on is kept in no other name on this machine';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? branch = _named(context);
    if (branch == null) {
      return CheckResult.blocked(
        'this run holds no answer called "$nameAnswer", and that is where this row says the name '
        'of the branch comes from',
      );
    }

    final CommandResult head = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ]);
    if (!head.ok || head.trimmed.isEmpty) {
      return CheckResult.blocked(
        'nothing in $repository answers which branch it stands on, so there is no checkout here to '
        'stand on "$branch" — the row that places the checkout has still to run',
      );
    }

    final ({String commit, String? refusal}) published = await _published(context, branch);
    if (published.refusal case final String refusal) {
      return CheckResult.blocked(
        '$remote could not be asked where "$branch" stands, so nothing here says whether it '
        'publishes that branch at all: $refusal',
      );
    }
    if (published.commit.isEmpty) {
      return CheckResult.blocked(
        '$remote publishes no branch called "$branch", and this row stands a checkout on one that '
        'is already published — gate it on the condition that asks whether the remote carries the '
        'branch, and cut the branch on the other side of it',
      );
    }

    if (head.trimmed == branch && await _standingOn(context, branch) == published.commit) {
      return CheckResult.satisfied(
        '$repository stands on $branch at ${published.commit}, as $remote publishes it',
      );
    }

    // ASKED LAST, and only where there is work. A checkout already standing where this row says
    // changes nothing, so an edit somebody left in the tree is none of this row's business there.
    final CommandResult dirty = await _observe(context, <String>[
      '-C',
      repository,
      'status',
      '--porcelain',
    ]);
    if (!dirty.ok) {
      return CheckResult.blocked(
        'the state of the working tree at $repository could not be read, and this row would place a '
        'branch over it: ${dirty.stderr.trim()}',
      );
    }
    if (dirty.trimmed.isNotEmpty) {
      return CheckResult.blocked(
        'the working tree is not clean, and the branch this row places would carry changes nobody '
        'declared: ${dirty.trimmed.split('\n').join(', ')}',
      );
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? branch = _named(context);
    if (branch == null) {
      return StepPlan.nothing(
        'this run holds no answer called "$nameAnswer", so there is no branch to stand on',
      );
    }
    return StepPlan.argv(<String>[
      'git',
      '-C',
      repository,
      'checkout',
      '-B',
      branch,
      '$remote/$branch',
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String branch = context.answers.text(nameAnswer);
    // The destination is named outright rather than left to whatever the checkout's configuration
    // happens to map: a remote added by hand often maps nothing, and the placement below would then
    // read a name no fetch had moved.
    await _mustRun(context, <String>[
      '-C',
      repository,
      'fetch',
      remote,
      '+refs/heads/$branch:refs/remotes/$remote/$branch',
    ]);
    await _mustRun(context, <String>[
      '-C',
      repository,
      'checkout',
      '-B',
      branch,
      '$remote/$branch',
    ]);
  }

  /// The branch name this run answered, or null when the run holds no such answer.
  String? _named(StepContext context) =>
      context.answers.has(nameAnswer) ? context.answers.text(nameAnswer) : null;

  /// The commit the remote publishes [branch] on, the empty text where it publishes none, or why
  /// neither could be read.
  ///
  /// **AN EMPTY ANSWER IS AN ANSWER AND A NON-ZERO EXIT IS NOT.** `ls-remote` writes nothing at exit
  /// zero for a branch the remote does not publish, so the empty answer keeps meaning that. A
  /// non-zero exit is the remote not having been reached — no credential, no network, a host key it
  /// would not accept — and folded into the same empty text it would become a verdict about the
  /// remote out of a question nobody managed to put to it.
  Future<({String commit, String? refusal})> _published(StepContext context, String branch) async {
    final CommandResult listed = await _observe(context, <String>[
      '-C',
      repository,
      'ls-remote',
      '--heads',
      remote,
      'refs/heads/$branch',
    ]);
    if (!listed.ok) {
      return (
        commit: '',
        refusal:
            'git exited ${listed.exitCode}'
            '${listed.stderr.trim().isEmpty ? ' and wrote nothing' : ': ${listed.stderr.trim()}'}',
      );
    }
    for (final String line in listed.trimmed.split('\n')) {
      final List<String> parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[1] == 'refs/heads/$branch') {
        return (commit: parts[0], refusal: null);
      }
    }
    return (commit: '', refusal: null);
  }

  /// The commit this checkout resolves [branch] to, or the empty text where it resolves none.
  Future<String> _standingOn(StepContext context, String branch) async {
    final CommandResult resolved = await _observe(context, <String>[
      '-C',
      repository,
      'rev-parse',
      '--quiet',
      '--verify',
      'refs/heads/$branch^{commit}',
    ]);
    return resolved.ok ? resolved.trimmed : '';
  }

  Future<CommandResult> _observe(StepContext context, List<String> argv) =>
      context.shell.run(Command.observing('git', arguments: argv));

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command('git', argv));
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}
