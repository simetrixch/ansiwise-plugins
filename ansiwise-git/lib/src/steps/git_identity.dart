import 'package:ansiwise_api/ansiwise_api.dart';

/// Sets the name and mailbox a checkout makes its commits as.
///
/// **Whatever a run produces in a checkout leaves it as a commit, and a commit needs an identity.**
/// Without one git refuses at the moment of committing — after the branch was cut and every file in
/// it was rewritten — so the run has already done all of its work by the time it learns it cannot
/// keep any of it.
///
/// **Set here rather than required of an operator.** Asking for it is one more thing a person has to
/// do on a machine before the program will run, and a machine prepared by hand is a machine whose
/// preparation nobody can repeat. Everything an installation needs comes from an answer or from a
/// step; a `git config` typed into a session is neither.
///
/// **Local to the checkout, never global.** A machine may hold several checkouts and only one of
/// them is this installation's. Writing the identity into the account's own configuration would
/// reach every repository the operator ever clones there, which is a decision about their machine
/// that a deployment has no business making.
///
/// **The undo puts back exactly what stood there.** A checkout that already had an identity keeps
/// it, because it is somebody's own and this run did not create it; a checkout that had none has the
/// setting removed rather than emptied — git reads an empty value as set and everything else reads
/// it as unset, which is the one state that satisfies neither.
final class GitIdentity extends ReversibleStep<GitIdentityBefore> {
  /// Sets the committer identity of the checkout at [repository] from the answers this row names.
  const GitIdentity({
    required this.repository,
    required this.nameAnswer,
    required this.emailAnswer,
  });

  /// Builds the step from what the program gave it.
  factory GitIdentity.fromArguments(Arguments arguments) => GitIdentity(
    repository: arguments.text('repository'),
    nameAnswer: arguments.text('name_answer'),
    emailAnswer: arguments.text('email_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose committer identity is set',
    ),
    ArgumentSpec(
      name: 'name_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the name commits are made under. It is a name a person '
          'reads in a history, so it belongs to the installation and not to this package',
    ),
    ArgumentSpec(
      name: 'email_answer',
      kind: ArgumentKind.answerName,
      describes: 'the name of the answer holding the mailbox commits are made under',
    ),
  ];

  /// The checkout being set.
  final String repository;

  /// WHICH answer holds the committer name.
  final String nameAnswer;

  /// WHICH answer holds the committer mailbox.
  final String emailAnswer;

  /// The two settings, in the order git takes them.
  static const String nameKey = 'user.name';

  /// The mailbox setting's key.
  static const String emailKey = 'user.email';

  @override
  Future<CheckResult> check(StepContext context) async {
    // Asked first, so a path that is not a checkout at all is refused as that rather than as a
    // missing identity: `git -C` on a directory that does not exist fails every read after it.
    final CommandResult checkout = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', '--git-dir']),
    );
    if (!checkout.ok) {
      return CheckResult.blocked(
        'there is no git checkout at $repository: ${checkout.stderr.trim()}',
      );
    }

    final String wantedName = context.answers.text(nameAnswer);
    final String wantedEmail = context.answers.text(emailAnswer);
    final String? name = await configured(context, nameKey);
    final String? email = await configured(context, emailKey);
    return name == wantedName && email == wantedEmail
        ? CheckResult.satisfied('commits in $repository are made as $name <$email>')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>[
    'git',
    '-C',
    repository,
    'config',
    nameKey,
    context.answers.text(nameAnswer),
  ]);

  @override
  Future<void> apply(StepContext context) async {
    await _set(context, nameKey, context.answers.text(nameAnswer));
    await _set(context, emailKey, context.answers.text(emailAnswer));
  }

  /// What stood in the checkout before this run, so the undo can put exactly that back.
  @override
  Future<GitIdentityBefore> capture(StepContext context) async => GitIdentityBefore(
    name: await configured(context, nameKey),
    email: await configured(context, emailKey),
  );

  @override
  Future<void> undo(StepContext context, GitIdentityBefore captured) async {
    await _restore(context, nameKey, captured.name);
    await _restore(context, emailKey, captured.email);
  }

  /// What git resolves for [key] in this checkout, or null when it resolves to nothing.
  ///
  /// A key set to the empty string reads as set to git and as unset to everybody else, so an empty
  /// answer counts as no answer.
  Future<String?> configured(StepContext context, String key) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'config', '--get', key]),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  Future<void> _set(StepContext context, String key, String value) async {
    final Command set = Command.detailed(
      'git',
      arguments: <String>['-C', repository, 'config', key, value],
    );
    final CommandResult done = await context.shell.run(set);
    if (!done.ok) {
      throw CommandFailed(argv: set.argv, exitCode: done.exitCode, stdout: '', stderr: done.stderr);
    }
  }

  /// Puts [key] back to [held], or takes the setting out where there was none.
  Future<void> _restore(StepContext context, String key, String? held) async {
    if (held case final String value) {
      await _set(context, key, value);
      return;
    }
    await context.shell.run(
      Command.detailed('git', arguments: <String>['-C', repository, 'config', '--unset', key]),
    );
  }
}

/// The identity a checkout carried before this run, which is what the undo puts back.
final class GitIdentityBefore {
  /// Records the [name] and [email] that stood in the checkout, either of them null where none did.
  const GitIdentityBefore({required this.name, required this.email});

  /// The name that stood there, or null where none did.
  final String? name;

  /// The mailbox that stood there, or null where none did.
  final String? email;
}
