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
  /// Refuses a machine on which any of [commands] is not on the path, naming for each of
  /// [providedBy] the package that carries it.
  const RequireCommands(this.commands, {this.providedBy = const <String>[]});

  /// Builds the step from what the program gave it.
  factory RequireCommands.fromArguments(Arguments arguments) => RequireCommands(
    arguments.textList('commands'),
    providedBy: arguments.textList('provided_by'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'commands',
      kind: ArgumentKind.textList,
      describes: 'the commands that have to be on the path before anything else runs',
    ),
    // Which package carries a command is a fact of ONE distribution's archive, not of the machine
    // this step measures, so no table of them stands in this file. The empty list is the neutral
    // case and not a choice: it says every missing command is reported under its own name.
    ArgumentSpec(
      name: 'provided_by',
      kind: ArgumentKind.textList,
      describes:
          'the commands whose package is called something else, each written as the command, an '
          'equals sign and the package that carries it, such as htpasswd=apache2-utils — a missing '
          'command named here is reported with that package beside it',
      required: false,
      defaultValue: <String>[],
    ),
  ];

  /// The commands that have to be there.
  final List<String> commands;

  /// The commands whose package is called something else, each as `command=package`.
  final List<String> providedBy;

  /// [providedBy] read as the package carrying each command.
  ///
  /// An entry that does not read as a name, an equals sign and a package is left out rather than
  /// guessed at, so the command it was meant for is reported under its own name — which is what a
  /// step with no entry for it does anyway.
  Map<String, String> get packages {
    final Map<String, String> byCommand = <String, String>{};
    for (final String entry in providedBy) {
      final int equals = entry.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final String package = entry.substring(equals + 1).trim();
      if (package.isEmpty) {
        continue;
      }
      byCommand[entry.substring(0, equals).trim()] = package;
    }
    return byCommand;
  }

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> missing = <String>[];
    final List<String> found = <String>[];
    final Map<String, String> packages = this.packages;

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
    return CheckResult.blocked(
      'not on the path: ${missing.map((String command) => _named(command, packages)).join(', ')}',
    );
  }

  static String _named(String command, Map<String, String> packages) {
    final String? package = packages[command];
    return package == null ? command : '$command (from $package)';
  }
}
