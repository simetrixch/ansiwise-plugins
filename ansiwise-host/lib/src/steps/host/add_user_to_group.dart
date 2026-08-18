import 'package:ansiwise_core/ansiwise_core.dart';

import 'install_authorized_key.dart';

/// Lets the operator's account use the cluster without becoming root for it.
///
/// The snap creates a group and only its members may talk to the cluster. Without this every command
/// an operator types answers with a refusal that says nothing about a group.
///
/// The membership takes effect at the next login, which is why the step reports it: an operator who
/// runs the next command in the session that is already open still meets the refusal.
final class AddUserToGroup extends ReversibleStep<bool> {
  /// Puts the operator's account in [group].
  const AddUserToGroup({required this.group});

  /// Builds the step from what the program gave it.
  factory AddUserToGroup.fromArguments(Arguments arguments) =>
      AddUserToGroup(group: arguments.text('group'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default: which group guards the cluster is the installed tool's fact, and the program
    // row states it.
    ArgumentSpec(
      name: 'group',
      kind: ArgumentKind.text,
      describes: 'the group whose members may talk to the cluster',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account is the one the machine's provider made and the operator reaches it through, so it
  /// is answered by whoever runs this and never written into a program file.
  static const List<String> answers = <String>[InstallAuthorizedKey.userAnswer];

  /// The group whose members may talk to the cluster.
  final String group;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult account = await context.shell.run(
      Command.observing(
        'getent',
        arguments: <String>['passwd', InstallAuthorizedKey.userIn(context)],
      ),
    );
    if (!account.ok || account.trimmed.isEmpty) {
      return CheckResult.blocked(
        'there is no account called ${InstallAuthorizedKey.userIn(context)} on this machine',
      );
    }

    final CommandResult groups = await context.shell.run(
      Command.observing('groups', arguments: <String>[InstallAuthorizedKey.userIn(context)]),
    );
    if (!groups.ok) {
      return CheckResult.blocked(
        "the groups of ${InstallAuthorizedKey.userIn(context)} could not be read: ${groups.stderr.trim()}",
      );
    }
    if (groups.stdout.split(RegExp(r'[\s:]+')).contains(group)) {
      return CheckResult.satisfied('${InstallAuthorizedKey.userIn(context)} is in $group');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_add(context));

  @override
  Future<void> apply(StepContext context) async {
    final List<String> argv = _add(context);
    final CommandResult added = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
    if (!added.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: added.exitCode,
        stdout: added.stdout,
        stderr: added.stderr,
      );
    }
    context.log.info(
      '${InstallAuthorizedKey.userIn(context)} is in $group from the next login on — a session that is already open still meets the '
      'refusal',
    );
  }

  /// Whether the account is in the group already.
  ///
  /// The undo takes the account out again, and an account that carried the membership before this
  /// ran would lose one this step never gave it.
  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult groups = await context.shell.run(
      Command.observing('groups', arguments: <String>[InstallAuthorizedKey.userIn(context)]),
    );
    return groups.ok && groups.stdout.split(RegExp(r'[\s:]+')).contains(group);
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command.detailed(
        'gpasswd',
        arguments: <String>['--delete', InstallAuthorizedKey.userIn(context), group],
        elevated: true,
      ),
    );
  }

  /// Appends the group rather than replacing the account's groups, which is what a missing
  /// `--append` would silently do — leaving the account in this group and in nothing else.
  List<String> _add(StepContext context) => <String>[
    'usermod',
    '--append',
    '--groups',
    group,
    InstallAuthorizedKey.userIn(context),
  ];
}
