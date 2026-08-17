import 'package:ansiwise_api/ansiwise_api.dart';

import 'install_authorized_key.dart';

/// Lets the operator type the ordinary name of a tool the cluster ships under its own.
///
/// **A shell startup file this machine does not have is never created.** Creating one would put a
/// file into an account that deliberately has none, and everything that account's shell then does
/// would be decided by a file this program wrote. So a missing one is skipped, and the account keeps
/// whatever shell arrangement it had.
final class AddShellAlias extends ReversibleStep<List<String>> {
  /// Makes [alias] run [command] for the operator's account.
  const AddShellAlias({required this.alias, required this.command, required this.rcFiles});

  /// Builds the step from what the program gave it.
  factory AddShellAlias.fromArguments(Arguments arguments) => AddShellAlias(
    alias: arguments.text('alias'),
    command: arguments.text('command'),
    rcFiles: arguments.textList('rc_files'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(name: 'alias', kind: ArgumentKind.text, describes: 'the name the operator types'),
    ArgumentSpec(name: 'command', kind: ArgumentKind.text, describes: 'what that name runs'),
    ArgumentSpec(
      name: 'rc_files',
      kind: ArgumentKind.textList,
      describes:
          'the shell startup files it is written into, each one only where it already exists',
      required: false,
      defaultValue: <String>['.bashrc', '.zshrc'],
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account is the one the machine's provider made and the operator reaches it through, so it
  /// is answered by whoever runs this and never written into a program file.
  static const List<String> answers = <String>[InstallAuthorizedKey.userAnswer];

  /// The name the operator types.
  final String alias;

  /// What that name runs.
  final String command;

  /// The shell startup files it goes into.
  final List<String> rcFiles;

  /// The line this step writes.
  String get line => "alias $alias='$command'";

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? home = await homeOf(context, InstallAuthorizedKey.userIn(context));
    if (home == null) {
      return CheckResult.blocked(
        'there is no account called ${InstallAuthorizedKey.userIn(context)} on this machine',
      );
    }
    final List<String> present = await _present(context, home);
    if (present.isEmpty) {
      return CheckResult.satisfied(
        '${InstallAuthorizedKey.userIn(context)} has none of ${rcFiles.join(', ')}, and this never creates one',
      );
    }
    final List<String> missing = await _missing(context, present);
    if (missing.isEmpty) {
      return CheckResult.satisfied('$alias runs $command in ${present.join(', ')}');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? home = await homeOf(context, InstallAuthorizedKey.userIn(context));
    final List<String> missing = home == null
        ? const <String>[]
        : await _missing(context, await _present(context, home));
    return StepPlan.diff(
      missing.isEmpty ? '${home ?? ''}/${rcFiles.first}' : missing.first,
      before: missing.isEmpty ? line : await context.files.read(missing.first),
      after: missing.isEmpty ? line : '${await context.files.read(missing.first)}$line\n',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? home = await homeOf(context, InstallAuthorizedKey.userIn(context));
    if (home == null) {
      return;
    }
    for (final String path in await _missing(context, await _present(context, home))) {
      final String current = await context.files.read(path);
      final String body = current.isEmpty || current.endsWith('\n') ? current : '$current\n';
      await context.files.write(path, '$body$line\n', mode: _rcFileMode);
    }
  }

  /// The startup files that do not carry the line yet, which are the ones the apply writes into.
  ///
  /// The undo takes the line out of exactly these. A file that already carried it was written by
  /// something else, and stripping the line there would take away an alias this run never added.
  @override
  Future<List<String>> capture(StepContext context) async {
    final String? home = await homeOf(context, InstallAuthorizedKey.userIn(context));
    if (home == null) {
      return const <String>[];
    }
    return _missing(context, await _present(context, home));
  }

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    for (final String path in captured) {
      if (!await context.files.exists(path)) {
        continue;
      }
      final String current = await context.files.read(path);
      if (!current.contains(line)) {
        continue;
      }
      await context.files.write(
        path,
        current.split('\n').where((String each) => each.trim() != line).join('\n'),
        mode: _rcFileMode,
      );
    }
  }

  /// Where [user] lives, or null when there is no such account.
  ///
  /// Read out of the account itself rather than composed from the name: an account's home is not
  /// always under the directory the name would suggest, and writing into the one it is not is
  /// writing into somebody else's.
  static Future<String?> homeOf(StepContext context, String user) async {
    final CommandResult account = await context.shell.run(
      Command.observing(
        'getent',
        arguments: <String>['passwd', InstallAuthorizedKey.userIn(context)],
      ),
    );
    if (!account.ok) {
      return null;
    }
    final List<String> fields = account.trimmed.split(':');
    return fields.length >= 6 && fields[5].isNotEmpty ? fields[5] : null;
  }

  Future<List<String>> _present(StepContext context, String home) async => <String>[
    for (final String name in rcFiles)
      if (await context.files.exists('$home/$name')) '$home/$name',
  ];

  Future<List<String>> _missing(StepContext context, List<String> present) async => <String>[
    for (final String path in present)
      if (!(await context.files.read(path)).split('\n').any((String each) => each.trim() == line))
        path,
  ];

  /// `0644` — a shell startup file the account's own shell reads.
  static const int _rcFileMode = 0x1a4;
}
