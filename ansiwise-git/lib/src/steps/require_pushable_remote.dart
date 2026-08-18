import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a run whose result could not be pushed, before any of that result exists.
///
/// **This is the gate a whole preflight can be built around.** The failure it prevents was observed:
/// the work was done, the commit was made, and only then was the push refused — no write access, or
/// the remote had moved ahead — leaving the commit stranded on the machine. A branch that was
/// generated and then cannot be pushed is the worst of both outcomes: what it was cut from is
/// untouched, the result is not published, and somebody has to unpick a local branch by hand.
///
/// **The proof is a dry run, because nothing else can prove it this early.** Write access is a
/// property of the remote and the credential, and the only way to ask about it without changing
/// anything is to offer a push and let the remote answer. `git push --dry-run` performs the whole
/// exchange and updates nothing, which is why it is declared as a command that only looks.
///
/// The three questions are asked in order and not in parallel, because each is meaningless without
/// the one before it: there is no reachability without a remote, and no push without reachability.
final class RequirePushableRemote extends ObservingStep {
  /// Refuses unless [branch] could be pushed to [remote] from the checkout at [repository].
  const RequirePushableRemote({
    required this.repository,
    required this.remote,
    required this.branch,
  });

  /// Builds the step from what the program gave it.
  factory RequirePushableRemote.fromArguments(Arguments arguments) => RequirePushableRemote(
    repository: arguments.text('repository'),
    remote: arguments.text('remote'),
    branch: arguments.text('branch'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout a push would come from',
    ),
    // A checkout may have any number of remotes under any name. `origin` is the name git's own
    // clone gives the one it copied from, and a checkout made some other way carries whatever name
    // was chosen — so the name is read from the row rather than assumed to be that one.
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      describes: 'the name of the remote the push is offered to, as this checkout holds it',
    ),
    ArgumentSpec(
      name: 'branch',
      kind: ArgumentKind.text,
      describes: 'the branch a push has to be accepted for',
    ),
  ];

  /// The checkout the push would come from.
  final String repository;

  /// The name the checkout holds the remote under.
  final String remote;

  /// The branch the push is offered for.
  final String branch;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult address = await _git(context, <String>['remote', 'get-url', remote]);
    if (!address.ok) {
      return CheckResult.blocked(
        'this checkout has no remote called "$remote", and the branch this run produces has nowhere '
        'to go: ${address.stderr.trim()}',
      );
    }

    final CommandResult reachable = await _git(context, <String>['ls-remote', '--heads', remote]);
    if (!reachable.ok) {
      return CheckResult.blocked(
        '${address.trimmed} does not answer, so nothing about a push can be decided: '
        '${reachable.stderr.trim()}',
      );
    }

    final CommandResult offered = await _git(context, <String>[
      'push',
      '--dry-run',
      remote,
      branch,
    ]);
    if (!offered.ok) {
      return CheckResult.blocked(
        '${address.trimmed} would refuse a push of $branch — either this credential may not write '
        'there, or $remote/$branch has moved ahead of this checkout: ${offered.stderr.trim()}',
      );
    }

    return CheckResult.satisfied('${address.trimmed} answers and would accept a push');
  }

  /// Runs a git command that reaches the remote, and cannot stop to ask anybody anything.
  ///
  /// There is no terminal on the other side of this: the run comes from a session a client opened,
  /// so a credential prompt or an unknown-host question does not fail the run, it hangs it until the
  /// deadline. `GIT_TERMINAL_PROMPT=0` turns git's own prompt into a refusal and `BatchMode=yes`
  /// does the same for the passphrase and host-key questions ssh would otherwise ask.
  Future<CommandResult> _git(StepContext context, List<String> arguments) => context.shell.run(
    Command.detailed(
      'git',
      arguments: <String>['-C', repository, ...arguments],
      environment: _nonInteractive,
      observes: true,
      timeout: _deadline,
    ),
  );

  /// What stops git asking a question nobody is there to answer.
  static const Map<String, String> _nonInteractive = <String, String>{
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
  };

  /// How long the remote is given to answer.
  ///
  /// A remote that has not spoken in a minute is not slow, it is unreachable in a way that no
  /// further waiting resolves — and this gate exists to fail early rather than to be thorough.
  static const Duration _deadline = Duration(minutes: 1);
}
