import 'package:ansiwise_core/ansiwise_core.dart';
import 'install_tool_prerequisites.dart';
import 'require_cli_tool_versions.dart';

/// Puts the private-network client on the machine, using the installer its makers publish.
///
/// **With a version, the version decides whether to install it.** The installer is handed the pin
/// in `TAILSCALE_VERSION` and passes it to the package manager, so a machine set up today and one
/// set up next month carry the same client, and a re-run brings a machine that drifted back to the
/// pin. A pin older than the client that stands there is refused by the package manager, which
/// steps a package down only when told to.
///
/// **Without one, its presence decides**, and whatever the installer fetches on the day is what
/// lands.
///
/// **Being installed says nothing about being on a network.** The service runs from the moment it is
/// installed and belongs to nothing until a credential has been used to join, which is a separate
/// fact and is reported separately.
///
/// The installer is fetched to a file first rather than fed straight into a shell, so what ran is
/// still on the machine to be looked at when something about it goes wrong.
final class InstallTailscaleClient extends IrreversibleStep {
  /// Puts the client on the machine from [installerUrl], at [version] where the row names one.
  const InstallTailscaleClient({
    required this.installerUrl,
    required this.installerPath,
    required this.pinPrefixes,
    this.version,
  });

  /// Builds the step from what the program gave it.
  factory InstallTailscaleClient.fromArguments(Arguments arguments) => InstallTailscaleClient(
    installerUrl: arguments.text('installer_url'),
    installerPath: arguments.text('installer_path'),
    pinPrefixes: arguments.textList('pin_prefixes'),
    version: arguments.optionalText('version'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'installer_url',
      kind: ArgumentKind.text,
      describes: 'the installer its makers publish',
      required: false,
      defaultValue: 'https://tailscale.com/install.sh',
    ),
    ArgumentSpec(
      name: 'installer_path',
      kind: ArgumentKind.text,
      describes: 'where the installer is put before it is run, so what ran can be looked at',
      required: false,
      defaultValue: '/tmp/tailscale-install.sh',
    ),
    ArgumentSpec(
      name: 'version',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the version the program pins for the client, handed to the installer. Without one, '
          'a client that is there is left alone and a new one is whatever the installer fetches',
    ),
    // No default, for the reason the step that fetches pinned releases gives: which tag shapes are
    // in play is decided by the tools the program pins, so the list stands once in the program.
    ArgumentSpec(
      name: 'pin_prefixes',
      kind: ArgumentKind.textList,
      describes:
          'the shapes a release tag is written with, taken off the pin before it is handed to the '
          'installer and held against what the client answers — such as v for v1.102.4',
    ),
  ];

  /// What the tool is called.
  static const String tool = 'tailscale';

  /// The service that runs from the moment the client is installed.
  static const String service = 'tailscaled';

  /// The variable the installer reads the version to install from.
  static const String versionVariable = 'TAILSCALE_VERSION';

  /// What the client is asked its version with. Its first line is the bare version.
  static const List<String> versionCommand = <String>['version'];

  /// The installer its makers publish.
  final String installerUrl;

  /// Where the installer is put.
  final String installerPath;

  /// The version the program pins, or null where the row names none.
  final String? version;

  /// The shapes a release tag is written with, taken off the pin.
  final List<String> pinPrefixes;

  /// The pin without the shape its release tag carries, which is how the installer and the client
  /// both write a version, or null where the row names no version.
  String? get _pinned =>
      version == null ? null : RequireCliToolVersions.bare(version!, pinPrefixes);

  @override
  String get irreversibleReason =>
      'the package manager puts the client over whatever version of it stood there, and keeps no '
      'copy of the one it replaced';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? pinned = _pinned;
    if (pinned == null) {
      return await InstallToolPrerequisites.onPath(context, tool)
          ? const CheckResult.satisfied('$tool is on the path')
          : const CheckResult.ready();
    }
    if (pinned.isEmpty) {
      return const CheckResult.blocked(
        'the row gives $tool an empty version, and the installer would read that as no version and '
        'fetch whatever is current',
      );
    }
    final String? installed = (await RequireCliToolVersions.installedVersion(
      context,
      tool,
      versionCommand,
    )).version;
    return installed == pinned
        ? CheckResult.satisfied('$tool is at $installed')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>[
    if (_pinned case final String pinned) ...<String>['env', '$versionVariable=$pinned'],
    'sh',
    installerPath,
  ]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>[
      'curl',
      '--silent',
      '--show-error',
      '--fail',
      '--location',
      '--output',
      installerPath,
      installerUrl,
    ]);
    await _mustRun(
      context,
      <String>['sh', installerPath],
      environment: <String, String>{if (_pinned case final String pinned) versionVariable: pinned},
    );
    await _mustRun(context, <String>['systemctl', 'enable', '--now', service]);
    context.log.info(
      '$tool is installed and $service is running. It belongs to no network until a join credential '
      'has been used — that is a separate fact from this one.',
    );
  }

  Future<void> _mustRun(
    StepContext context,
    List<String> argv, {
    Map<String, String> environment = const <String, String>{},
  }) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(
        argv.first,
        arguments: argv.sublist(1),
        environment: environment,
        elevated: true,
      ),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}
