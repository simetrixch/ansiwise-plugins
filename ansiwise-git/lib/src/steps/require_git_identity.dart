import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a checkout that has nobody to make a commit as.
///
/// Whatever a run produces in a checkout leaves it as a commit, and a commit needs a name and a
/// mailbox. Without them git refuses at the moment of committing — which is after the branch was cut
/// and every file in it was rewritten, so the run has already done all of its work by the time it
/// learns it cannot keep any of it.
///
/// **Both are reported at once.** An operator told about the name, who sets it, runs again and is
/// then told about the mailbox has paid for two runs to learn what one could have said.
final class RequireGitIdentity extends ObservingStep {
  /// Refuses a run against the checkout at [repository] that has no committer identity.
  const RequireGitIdentity(this.repository);

  /// Builds the step from what the program gave it.
  factory RequireGitIdentity.fromArguments(Arguments arguments) =>
      RequireGitIdentity(arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose committer identity is read',
    ),
  ];

  /// The checkout whose identity is being read.
  final String repository;

  @override
  Future<CheckResult> check(StepContext context) async {
    // Asked first, so that a path which is not a checkout at all is refused as that rather than as a
    // missing identity. `git -C` on a directory that does not exist fails every read after it, and
    // the refusal would otherwise name two settings the operator has already set.
    final CommandResult checkout = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'rev-parse', '--git-dir']),
    );
    if (!checkout.ok) {
      return CheckResult.blocked(
        'there is no git checkout at $repository: ${checkout.stderr.trim()}',
      );
    }

    final String? name = await _configured(context, 'user.name');
    final String? email = await _configured(context, 'user.email');
    if (name != null && email != null) {
      return CheckResult.satisfied('commits will be made as $name <$email>');
    }

    final List<String> unset = <String>[
      if (name == null) 'git -C $repository config user.name "Your Name"',
      if (email == null) 'git -C $repository config user.email "you@example.com"',
    ];
    return CheckResult.blocked(
      'this checkout has no committer identity, and every branch this run produces is a commit: '
      '${unset.join('; ')}',
    );
  }

  /// What git resolves for [key] here, or null when it resolves to nothing.
  ///
  /// A key set to the empty string reads as set to git and as unset to everybody else, so an empty
  /// answer counts as no answer.
  Future<String?> _configured(StepContext context, String key) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'config', '--get', key]),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }
}
