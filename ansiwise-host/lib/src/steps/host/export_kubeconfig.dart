import 'package:ansiwise_api/ansiwise_api.dart';

import 'add_shell_alias.dart';
import 'install_authorized_key.dart';

/// Writes the credentials for this cluster where the operator's own tools look for them.
///
/// **The file is replaced whole, and that is what makes this step one to run deliberately.** It is
/// the file every tool an operator runs reads, so a context they added for another cluster, or an
/// edit they made by hand, is gone the moment this runs. Nothing merges into it and nothing keeps a
/// copy.
///
/// The file carries credentials that reach the whole cluster, so it is readable by its owner alone
/// and the directory it sits in is theirs.
///
/// **Which command hands the credentials over is an argument, and there is no default for it.** This
/// package drives a machine and owns no cluster client, so it has no invocation of its own to fall
/// back on: a distribution that ships the client inside a snap, one that expects a plain client on
/// the path, and one that reads a file put there by something else are three different command
/// lines, and only the program that installed the cluster knows which of them this machine has.
final class ExportKubeconfig extends IrreversibleStep {
  /// Writes the credentials [credentialsCommand] prints into the operator's home.
  const ExportKubeconfig({required this.credentialsCommand});

  /// Builds the step from what the program gave it.
  ///
  /// An empty list is refused here, before anything runs: it would name no word to start at all,
  /// and every step is constructed before the first one runs, so the refusal reaches the operator
  /// as a broken program rather than as a step failing halfway through an installation.
  factory ExportKubeconfig.fromArguments(Arguments arguments) {
    final List<String> command = arguments.textList('credentials_command');
    if (command.isEmpty) {
      throw ArgumentError.value(
        command,
        'credentials_command',
        'names no word at all, so there is nothing to ask the cluster for its credentials with',
      );
    }
    return ExportKubeconfig(credentialsCommand: command);
  }

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'credentials_command',
      kind: ArgumentKind.textList,
      describes:
          'the command that prints this cluster\'s credentials, word by word — it is run and its '
          'whole output is what the file holds, so it must print the credentials and nothing else',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account is the one the machine's provider made and the operator reaches it through, so it
  /// is answered by whoever runs this and never written into a program file.
  static const List<String> answers = <String>[InstallAuthorizedKey.userAnswer];

  /// The directory under the account's home that holds the credentials.
  ///
  /// Not an argument: this is the place the client reads when nothing points it elsewhere, the same
  /// on every machine and for every product, so a run that wrote anywhere else would leave the
  /// operator's tools finding nothing.
  static const String directoryName = '.kube';

  /// `0700` — a directory holding credentials to the whole cluster.
  static const int directoryMode = 0x1c0;

  /// `0600` — the credentials themselves.
  static const int fileMode = 0x180;

  /// The command that prints this cluster's credentials, word by word.
  final List<String> credentialsCommand;

  @override
  String get irreversibleReason =>
      'the file is replaced whole. Every context the operator added for another cluster and every '
      'edit they made by hand is gone, and nothing on the machine holds a copy of what was there';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? home = await AddShellAlias.homeOf(context, InstallAuthorizedKey.userIn(context));
    if (home == null) {
      return CheckResult.blocked(
        'there is no account called ${InstallAuthorizedKey.userIn(context)} on this machine',
      );
    }
    final String path = '$home/$directoryName/config';
    final String? wanted = await _credentials(context);
    if (wanted == null) {
      return const CheckResult.blocked(
        'the cluster would not hand out its credentials, so there is nothing to write',
      );
    }
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }
    return await context.files.read(path) == wanted
        ? CheckResult.satisfied('$path already holds this cluster\'s credentials')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? home = await AddShellAlias.homeOf(context, InstallAuthorizedKey.userIn(context));
    final String path = '${home ?? ''}/$directoryName/config';
    final String before = await context.files.exists(path) ? await context.files.read(path) : '';
    // What the file would hold is left out of the plan. It is a credential to the whole cluster, and
    // a plan is read by a person and reaches the record.
    return StepPlan.diff(
      path,
      before: before.isEmpty ? '' : '<the credentials that are there now>',
      after: "<this cluster's credentials>",
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? home = await AddShellAlias.homeOf(context, InstallAuthorizedKey.userIn(context));
    if (home == null) {
      return;
    }
    final String? credentials = await _credentials(context);
    if (credentials == null) {
      throw CommandFailed(
        argv: credentialsCommand,
        exitCode: 1,
        stdout: '',
        stderr: 'the cluster would not hand out its credentials',
      );
    }
    final String directory = '$home/$directoryName';
    context.log.warn(
      '$directory/config is replaced whole — any context added for another cluster is gone with it',
    );
    await context.files.createDirectory(directory, mode: directoryMode);
    await context.files.write('$directory/config', credentials, mode: fileMode);
    await context.shell.run(
      Command.detailed(
        'chown',
        arguments: <String>[
          '-R',
          '${InstallAuthorizedKey.userIn(context)}:${InstallAuthorizedKey.userIn(context)}',
          directory,
        ],
        elevated: true,
      ),
    );
  }

  /// The credentials the cluster hands out, or null when it will not.
  Future<String?> _credentials(StepContext context) async {
    final CommandResult config = await context.shell.run(
      Command.observing(credentialsCommand.first, credentialsCommand.sublist(1)),
    );
    return config.ok && config.stdout.trim().isNotEmpty ? config.stdout : null;
  }
}
