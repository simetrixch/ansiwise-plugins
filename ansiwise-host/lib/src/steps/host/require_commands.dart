import 'package:ansiwise_api/ansiwise_api.dart';

/// Refuses a machine that does not carry every command the later steps need.
///
/// **Every missing command at once, never the first one.** An operator who is told about `git`,
/// installs it, runs again and is then told about `openssl` has paid for two runs to learn what one
/// could have said. The resolver refuses a program the same way, for the same reason.
///
/// **The verdict comes from the command being on the path, never from what a package manager
/// returned.** The shell this replaces learned that on a machine: its own comment says the failure
/// branch fires "when apt did not produce the command". An install can succeed and leave nothing
/// behind.
///
/// This step only measures. Installing what is missing is a different step, and keeping the two
/// apart is what lets a dry run say what would be installed without installing it.
final class RequireCommands extends ObservingStep {
  /// Refuses a machine on which any of [commands] is not on the path.
  const RequireCommands(this.commands);

  /// Builds the step from what the program gave it.
  factory RequireCommands.fromArguments(Arguments arguments) =>
      RequireCommands(arguments.textList('commands'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'commands',
      kind: ArgumentKind.textList,
      describes: 'the commands that have to be on the path before anything else runs',
    ),
  ];

  /// Which package carries a command whose name is not the package's name.
  ///
  /// Knowledge and not configuration, which is why it is here rather than in a program file. An
  /// operator told to install `htpasswd` goes looking for a package that does not exist; told to
  /// install `apache2-utils`, they are done.
  static const Map<String, String> packages = <String, String>{'htpasswd': 'apache2-utils'};

  /// The commands that have to be there.
  final List<String> commands;

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> missing = <String>[];
    final List<String> found = <String>[];

    for (final String command in commands) {
      final CommandResult answer = await context.shell.run(
        Command.observing('command', <String>['-v', command]),
      );
      if (answer.ok && answer.trimmed.isNotEmpty) {
        found.add(command);
      } else {
        missing.add(command);
      }
    }

    if (missing.isEmpty) {
      return CheckResult.satisfied('${found.join(', ')} are on the path');
    }
    return CheckResult.blocked('not on the path: ${missing.map(_named).join(', ')}');
  }

  static String _named(String command) {
    final String? package = packages[command];
    return package == null ? command : '$command (from $package)';
  }
}
