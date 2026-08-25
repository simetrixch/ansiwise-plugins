import 'package:ansiwise_core/ansiwise_core.dart';

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
  const ExportKubeconfig({required this.credentialsCommand, this.elevated = false});

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
    return ExportKubeconfig(
      credentialsCommand: command,
      elevated: arguments.has('elevated') && arguments.flag('elevated'),
    );
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
    elevationArgument,
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

  /// Whether this row is reached as root rather than as the account the run started as.
  ///
  /// It covers both ports, and here the two point at different things: the command that hands the
  /// credentials over, and the file they are written into. A distribution that admits only root to
  /// its credentials is asked as root, and the file is then written as root into an account's home
  /// and handed to that account by the chown that closes [apply] — which is what lets one answer
  /// serve both.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'the file is replaced whole. Every context the operator added for another cluster and every '
      'edit they made by hand is gone, and nothing on the machine holds a copy of what was there';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? home, String? refusal}) account = await InstallAuthorizedKey.homeOf(context);
    if (account.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String path = '${account.home!}/$directoryName/config';
    final ({String? credentials, String said}) asked = await _credentials(context);
    final String? wanted = asked.credentials;
    if (wanted == null) {
      return CheckResult.blocked(
        'the cluster would not hand out its credentials, so there is nothing to write. '
        '${credentialsCommand.join(' ')} said: ${asked.said}',
      );
    }
    if (!await context.files.exists(path, elevated: elevated)) {
      return const CheckResult.ready();
    }
    return await context.files.read(path, elevated: elevated) == wanted
        ? CheckResult.satisfied('$path already holds this cluster\'s credentials')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ({String? home, String? refusal}) account = await InstallAuthorizedKey.homeOf(context);
    if (account.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final String path = '${account.home!}/$directoryName/config';
    final String before = await context.files.exists(path, elevated: elevated)
        ? await context.files.read(path, elevated: elevated)
        : '';
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
    final ({String? home, String? refusal}) account = await InstallAuthorizedKey.homeOf(context);
    if (account.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String home = account.home!;
    final ({String? credentials, String said}) asked = await _credentials(context);
    final String? credentials = asked.credentials;
    if (credentials == null) {
      throw CommandFailed(
        argv: credentialsCommand,
        exitCode: 1,
        stdout: '',
        stderr: 'the cluster would not hand out its credentials: ${asked.said}',
      );
    }
    final String directory = '$home/$directoryName';
    context.log.warn(
      '$directory/config is replaced whole — any context added for another cluster is gone with it',
    );
    await context.files.createDirectory(directory, mode: directoryMode, elevated: elevated);
    await context.files.write('$directory/config', credentials, mode: fileMode, elevated: elevated);
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

  /// The credentials the cluster hands out, or WHY it would not.
  ///
  /// **THE COMMAND'S OWN WORDS ARE CARRIED OUT OF HERE**, because they are the only thing that says
  /// which of several very different states this is. A cluster that is not running, an account the
  /// cluster distribution does not admit, a session that predates the group granting that
  /// admission — all three come back as a command that failed, and only one of them is about the
  /// cluster at all.
  ///
  /// The third costs the most and is the easiest to misread, and it is what [elevated] answers. A
  /// machine's first bring-up puts the operating account into the group the distribution grants
  /// access through, and supplementary groups are read once, when a session starts — so the session
  /// doing the granting does not carry it, and this command fails in a run where everything else
  /// succeeded. A row that says the distribution admits root reaches the credentials in that same
  /// session; a row that leaves it off still meets the refusal. Told only that "the cluster would
  /// not hand out its credentials", an operator goes and looks at a cluster that is perfectly
  /// healthy. Told what the command said, they read the distribution's own sentence about the group
  /// and log in again.
  Future<({String? credentials, String said})> _credentials(StepContext context) async {
    final CommandResult config = await context.shell.run(
      Command.observing(
        credentialsCommand.first,
        arguments: credentialsCommand.sublist(1),
        elevated: elevated,
      ),
    );
    if (config.ok && config.stdout.trim().isNotEmpty) {
      return (credentials: config.stdout, said: '');
    }
    // An empty answer from a command that SUCCEEDED says nothing at all, so it is named as that
    // rather than reported as a failure with no words behind it.
    final String said = config.stderr.trim().isNotEmpty
        ? config.stderr.trim()
        : config.ok
        ? 'it answered nothing at all'
        : 'it failed and said nothing';
    return (credentials: null, said: said);
  }
}
