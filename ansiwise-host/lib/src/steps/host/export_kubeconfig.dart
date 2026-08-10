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
final class ExportKubeconfig extends IrreversibleStep {
  /// Writes the credentials into the operator's home.
  const ExportKubeconfig();

  /// Builds the step from what the program gave it.
  factory ExportKubeconfig.fromArguments(Arguments arguments) => const ExportKubeconfig();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The account is the one the machine's provider made and the operator reaches it through, so it
  /// is answered by whoever runs this and never written into a program file.
  static const List<String> answers = <String>[InstallAuthorizedKey.userAnswer];

  /// The directory under the account's home that holds the credentials.
  static const String directoryName = '.kube';

  /// `0700` — a directory holding credentials to the whole cluster.
  static const int directoryMode = 0x1c0;

  /// `0600` — the credentials themselves.
  static const int fileMode = 0x180;

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
        argv: <String>['microk8s', 'config'],
        exitCode: 1,
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
      Command('chown', <String>[
        '-R',
        '${InstallAuthorizedKey.userIn(context)}:${InstallAuthorizedKey.userIn(context)}',
        directory,
      ]),
    );
  }

  /// The credentials the cluster hands out, or null when it will not.
  Future<String?> _credentials(StepContext context) async {
    final CommandResult config = await context.shell.run(
      const Command.observing('microk8s', <String>['config']),
    );
    return config.ok && config.stdout.trim().isNotEmpty ? config.stdout : null;
  }
}
