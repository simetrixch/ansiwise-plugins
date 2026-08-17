import 'package:ansiwise_api/ansiwise_api.dart';

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
    final String? local = await _localTip(context, branch);
    if (local == null) {
      return CheckResult.blocked('$repository has no commit on $branch to send');
    }
    return await _remoteTip(context, branch) == local
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
      Command('git', <String>['-C', repository, 'push', remote, branch]),
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
    final String? local = await _localTip(context, branch);
    final String? remoteTip = await _remoteTip(context, branch);
    if (remoteTip != local) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'ls-remote', '--heads', remote, branch],
        exitCode: 1,
        stdout: '',
        stderr:
            'the push reported success and $remote does not carry $branch at $local — it answers '
            '${remoteTip ?? 'nothing under that name'}. Whatever this run wrote is on this machine '
            'and nowhere else',
      );
    }
  }

  /// The branch this checkout stands on, or null where it stands on none.
  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    if (!answer.ok || answer.trimmed.isEmpty || answer.trimmed == 'HEAD') {
      return null;
    }
    return answer.trimmed;
  }

  /// The commit [branch] points at here, or null where it points at none.
  Future<String?> _localTip(StepContext context, String branch) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', branch]),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  /// The commit [remote] carries [branch] at, or null where it carries no such branch.
  Future<String?> _remoteTip(StepContext context, String branch) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'ls-remote', '--heads', remote, branch]),
    );
    if (!answer.ok || answer.trimmed.isEmpty) {
      return null;
    }
    return answer.trimmed.split(RegExp(r'\s+')).first;
  }
}
