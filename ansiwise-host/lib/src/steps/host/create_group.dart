import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts a group of a given number on the machine, so that an account can be made a member of it.
///
/// **THE NUMBER IS THE FACT AND THE NAME IS NOT.** A file's group is stored as a number, and a
/// process inside a container that writes a socket onto the host writes the number its own image
/// runs as — the host has no say in it and no name for it. So this step is satisfied by a group
/// carrying that number WHATEVER it is called: making a second one under the wanted name would give
/// the machine two names for one group and admit nobody to anything.
///
/// **What it is for.** `usermod --groups <number>` refuses a number no group carries, with
/// `group '<number>' does not exist` — and that is the whole of the failure it reports. The account
/// is fine, the socket is fine; there is simply nothing on the host to be a member OF.
///
/// **A name that is taken by another number is a refusal, not a second attempt.** `groupadd` would
/// fail on it anyway, and the reason a step can give — that this name is already a different group
/// — is worth more than the tool's exit code.
final class CreateGroup extends ReversibleStep<bool> {
  /// Puts a group called [name] carrying [gid] on the machine.
  const CreateGroup({required this.name, required this.gid});

  /// Builds the step from what the program gave it.
  factory CreateGroup.fromArguments(Arguments arguments) =>
      CreateGroup(name: arguments.text('name'), gid: arguments.text('gid'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'what the group is called on this machine. It is this installation\'s own word and '
          'nothing outside reads it — what admits an account is the number below',
    ),
    // TEXT AND NOT A NUMBER, because that is what every tool that reads it takes: `getent` is asked
    // for it as it stands and `groupadd` is handed it as it stands, and a number turned into text
    // here and back somewhere else is a step that agrees with the machine only by luck.
    ArgumentSpec(
      name: 'gid',
      kind: ArgumentKind.text,
      describes:
          'the number the group carries, which is the only part of it anything outside this machine '
          'knows — a file written by a process elsewhere carries a number and never a name',
    ),
  ];

  /// What the group is called.
  final String name;

  /// The number it carries.
  final String gid;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await _nameOf(context, gid) case final String existing) {
      return CheckResult.satisfied(
        existing == name
            ? '$name carries $gid on this machine'
            : 'a group carrying $gid is on this machine, called $existing rather than $name — the '
                  'number is what admits an account, so nothing is missing',
      );
    }
    if (await _gidOf(context, name) case final String taken) {
      return CheckResult.blocked(
        '$name is already a group on this machine and carries $taken, not $gid — one name cannot '
        'be two groups, and which of the two the installation means is not this step\'s to guess',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_add);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult added = await context.shell.run(
      Command.detailed(_add.first, arguments: _add.sublist(1), elevated: true),
    );
    if (!added.ok) {
      throw CommandFailed(
        argv: _add,
        exitCode: added.exitCode,
        stdout: added.stdout,
        stderr: added.stderr,
      );
    }
  }

  /// Whether a group already carried the number before this ran.
  ///
  /// The undo deletes the group, and one that was here first is one something else on this machine
  /// is using — an account's files carry the number, and taking it away leaves them owned by a
  /// group that no longer resolves.
  @override
  Future<bool> capture(StepContext context) async => await _nameOf(context, gid) != null;

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command.detailed('groupdel', arguments: <String>[name], elevated: true),
    );
  }

  /// The name of the group carrying [wanted], or null where no group does.
  Future<String?> _nameOf(StepContext context, String wanted) async =>
      _fieldOf(await _entry(context, wanted), 0);

  /// The number carried by the group called [wanted], or null where there is no such group.
  Future<String?> _gidOf(StepContext context, String wanted) async =>
      _fieldOf(await _entry(context, wanted), 2);

  Future<String?> _entry(StepContext context, String wanted) async {
    // `getent group` takes either a name or a number and answers the same line for both, which is
    // why one reader serves both questions. A group that is not there is exit 2 and no output.
    final CommandResult found = await context.shell.run(
      Command.observing('getent', arguments: <String>['group', wanted]),
    );
    return found.ok && found.trimmed.isNotEmpty ? found.trimmed : null;
  }

  /// Field [index] of a `getent group` line — `name:x:gid:members` — or null where there is none.
  static String? _fieldOf(String? entry, int index) {
    if (entry == null) {
      return null;
    }
    final List<String> fields = entry.split(':');
    return fields.length > index && fields[index].isNotEmpty ? fields[index] : null;
  }

  List<String> get _add => <String>['groupadd', '--gid', gid, name];
}
