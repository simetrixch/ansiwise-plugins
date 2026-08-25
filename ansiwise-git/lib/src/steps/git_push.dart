import 'package:ansiwise_core/ansiwise_core.dart';

/// Sends the branch this checkout stands on to the remote, and proves it arrived.
///
/// **What a run wrote is on ONE machine until this succeeds.** A program that cuts a branch, writes
/// into it and records it has produced nothing anybody else can reach — and the closing line says
/// exit 0 either way unless something asks the remote.
///
/// **It asks the remote afterwards rather than trusting the push.** `git push` answers 0 for a push
/// that had nothing to send, and that is the same answer as one that delivered — so the postcondition
/// is read from the remote: the branch is there, and it points at what this checkout points at. A
/// step that reported success on git's exit code alone would be right almost always and silently
/// wrong on the case that matters.
///
/// **The credential is not this step's business.** It knows how a push is made and what proves one
/// landed. How the machine is allowed to write to that remote is arranged before any program runs —
/// a key, a helper, an agent — and a step that carried a credential would make every caller hand it
/// one whether their remote wanted it or not.
///
/// **Refusing to be ASKED for a credential is not the same as carrying one.** There is no terminal
/// on the other side of a run a client opened, so a prompt does not fail the push — it hangs it
/// until the deadline, and the record then says nothing at all rather than "this credential may not
/// write there". So both commands that reach the network are told to refuse every question instead
/// of asking it, the same way the gate that offers a push is.
final class GitPush extends IrreversibleStep {
  /// Pushes the branch [repository] stands on to [remote].
  const GitPush({required this.repository, required this.remote});

  /// Builds the step from what the program gave it.
  factory GitPush.fromArguments(Arguments arguments) =>
      GitPush(repository: arguments.text('repository'), remote: arguments.text('remote'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose current branch is sent',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      describes:
          'the name this checkout holds the remote under. Stated rather than known: a clone calls '
          'it "origin" and a checkout made another way carries whatever name was chosen',
    ),
  ];

  /// The checkout.
  final String repository;

  /// The name of the remote in that checkout.
  final String remote;

  /// It sends what earlier steps recorded, so in a mode where they did not record, there is nothing.
  @override
  bool get restsOnAnEarlierStep => true;

  @override
  String get irreversibleReason =>
      'a branch on a remote is reachable by everything that fetches from it the moment it lands, so '
      'taking it back is a decision about that repository and about whoever already pulled — not a '
      'step this run may perform on its own';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? branch = await _head(context);
    if (branch == null) {
      return CheckResult.blocked('$repository stands on no branch, so there is none to send');
    }
    final ({String? commit, String? refusal}) local = await _localTip(context, branch);
    if (local.refusal case final String refusal) {
      return CheckResult.blocked(
        'what $branch stands on in $repository could not be read, so there is nothing to compare '
        'against what $remote carries: $refusal',
      );
    }
    if (local.commit == null) {
      return CheckResult.blocked('$repository has no commit on $branch to send');
    }
    final ({String? commit, String? refusal}) published = await _remoteTip(context, branch);
    if (published.refusal case final String refusal) {
      return CheckResult.blocked(
        '$remote could not be asked what it carries $branch at, so nothing here says whether the '
        'branch this run produced is already there: $refusal',
      );
    }
    return published.commit == local.commit
        ? CheckResult.satisfied('$remote already carries $branch at the commit this checkout is on')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? branch = await _head(context);
    if (branch == null) {
      return const StepPlan.nothing('would send the branch once one is cut and recorded');
    }
    return StepPlan.argv(<String>['git', '-C', repository, 'push', remote, branch]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String branch = (await _head(context))!;
    final CommandResult pushed = await context.shell.run(
      Command.detailed(
        'git',
        arguments: <String>['-C', repository, 'push', remote, branch],
        environment: _nonInteractive,
      ),
    );
    if (!pushed.ok) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'push', remote, branch],
        exitCode: pushed.exitCode,
        stdout: '',
        stderr: pushed.stderr,
      );
    }

    // THE POSTCONDITION, READ FROM THE REMOTE. git answers 0 for a push that sent nothing, and this
    // step exists to make the branch reachable — so what is asserted is that it IS reachable, at the
    // commit this checkout stands on, rather than that a command was content.
    //
    // TWO READINGS THAT COULD NOT BE TAKEN USED TO SATISFY IT. Both answered null where the command
    // failed, null equals null, and the assertion passed over two questions nobody managed to put —
    // which is a green verdict from a check that cannot go red, in the one place this step proves it
    // did its work. A reading that did not answer is now a failure of its own, naming which of the
    // two it was and what git said.
    final ({String? commit, String? refusal}) local = await _localTip(context, branch);
    if (local.refusal case final String refusal) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'rev-parse', branch],
        exitCode: 1,
        stdout: '',
        stderr:
            'the push reported success and this checkout could not then be asked what $branch '
            'stands on, so nothing proves $remote carries it: $refusal',
      );
    }
    final ({String? commit, String? refusal}) published = await _remoteTip(context, branch);
    if (published.refusal case final String refusal) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'ls-remote', '--heads', remote, branch],
        exitCode: 1,
        stdout: '',
        stderr:
            'the push reported success and $remote could not then be asked what it carries '
            '$branch at, so nothing proves what this run wrote left this machine: $refusal',
      );
    }
    if (published.commit != local.commit) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'ls-remote', '--heads', remote, branch],
        exitCode: 1,
        stdout: '',
        stderr:
            'the push reported success and $remote does not carry $branch at ${local.commit} — it '
            'answers ${published.commit ?? 'nothing under that name'}. Whatever this run wrote is '
            'on this machine and nowhere else',
      );
    }
  }

  /// The branch this checkout stands on, or null where it stands on none.
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

  /// The commit [branch] points at here, null where it points at none, or why neither was read.
  Future<({String? commit, String? refusal})> _localTip(StepContext context, String branch) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', branch]),
    );
    if (!answer.ok) {
      return (commit: null, refusal: _said(answer));
    }
    return (commit: answer.trimmed.isEmpty ? null : answer.trimmed, refusal: null);
  }

  /// The commit [remote] carries [branch] at, null where it carries no such branch, or why neither
  /// was read.
  ///
  /// **AN EMPTY ANSWER IS AN ANSWER HERE AND A NON-ZERO EXIT IS NOT.** `ls-remote` writes nothing at
  /// exit zero for a name the remote does not publish, so the empty answer keeps meaning that. A
  /// non-zero exit is the remote not having been reached — no credential, no network, a host key it
  /// would not accept — and it used to come back as the same null the empty answer does.
  Future<({String? commit, String? refusal})> _remoteTip(StepContext context, String branch) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        'git',
        arguments: <String>['-C', repository, 'ls-remote', '--heads', remote, branch],
        environment: _nonInteractive,
        observes: true,
      ),
    );
    if (!answer.ok) {
      return (commit: null, refusal: _said(answer));
    }
    if (answer.trimmed.isEmpty) {
      return (commit: null, refusal: null);
    }
    return (commit: answer.trimmed.split(RegExp(r'\s+')).first, refusal: null);
  }

  /// What git said about a reading that could not be taken, in its own words.
  static String _said(CommandResult answer) =>
      'git exited ${answer.exitCode}'
      '${answer.stderr.trim().isEmpty ? ' and wrote nothing' : ': ${answer.stderr.trim()}'}';

  /// What stops git asking a question nobody is there to answer.
  ///
  /// `GIT_TERMINAL_PROMPT=0` turns git's own credential prompt into a refusal, and `BatchMode=yes`
  /// does the same for the passphrase and host-key questions ssh would otherwise ask.
  static const Map<String, String> _nonInteractive = <String, String>{
    'GIT_TERMINAL_PROMPT': '0',
    'GIT_SSH_COMMAND': 'ssh -oBatchMode=yes',
  };
}
