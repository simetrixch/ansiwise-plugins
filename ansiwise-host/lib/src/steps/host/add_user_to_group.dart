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

    final String? gid = await _gidOf(context);
    if (gid == null) {
      return CheckResult.blocked(
        'no group on this machine is $group, so there is nothing for '
        '${InstallAuthorizedKey.userIn(context)} to be a member of — the step that makes the group '
        'has not run',
      );
    }

    final bool? member = await _isMember(context, gid);
    if (member == null) {
      return CheckResult.blocked(
        'the groups of ${InstallAuthorizedKey.userIn(context)} could not be read',
      );
    }
    return member
        ? CheckResult.satisfied('${InstallAuthorizedKey.userIn(context)} is in $group')
        : const CheckResult.ready();
  }

  /// The number the row's group carries, or null where no group on this machine is it.
  ///
  /// `getent group` answers the same line whether it was asked by name or by number, which is what
  /// lets a row state either.
  Future<String?> _gidOf(StepContext context) async {
    final CommandResult found = await context.shell.run(
      Command.observing('getent', arguments: <String>['group', group]),
    );
    if (!found.ok || found.trimmed.isEmpty) {
      return null;
    }
    final List<String> fields = found.trimmed.split(':');
    return fields.length > 2 && fields[2].isNotEmpty ? fields[2] : null;
  }

  /// Whether the account carries [gid], or null where its groups could not be read.
  ///
  /// **THE NUMBERS AND NOT THE NAMES.** `groups` prints names, and a row that states a NUMBER — as
  /// one must whenever the group belongs to something outside this machine, which writes a number
  /// onto it and was never told a name — is then compared against a list it can never appear in.
  /// The step ran, `usermod` succeeded, the account WAS a member, and the framework reported "the
  /// step ran and the machine is still not in the state it produces" on every run afterwards.
  /// `id -G` prints the numbers, and the row's group is resolved to one before the comparison, so a
  /// row may state either and both are read the same way.
  Future<bool?> _isMember(StepContext context, String gid) async {
    final CommandResult carried = await context.shell.run(
      Command.observing('id', arguments: <String>['-G', InstallAuthorizedKey.userIn(context)]),
    );
    if (!carried.ok) {
      return null;
    }
    return carried.stdout.split(RegExp(r'\s+')).contains(gid);
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
    if (await _gidOf(context) case final String gid) {
      return await _isMember(context, gid) ?? false;
    }
    return false;
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
