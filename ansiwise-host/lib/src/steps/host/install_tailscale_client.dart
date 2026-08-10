import 'package:ansiwise_api/ansiwise_api.dart';
import 'ensure_tool_prerequisites.dart';

/// Puts the private-network client on the machine, using the installer its makers publish.
///
/// **Its presence is what decides whether to install it, because the installer takes no version.**
/// Whatever is current at the moment it runs is what lands, so a machine set up today and one set up
/// next month carry different versions and nothing in a run can reach the pinned one. That is
/// reported by the step that holds every tool against its pin, and never failed on — an install that
/// failed on it could never end green anywhere.
///
/// **Being installed says nothing about being on a network.** The service runs from the moment it is
/// installed and belongs to nothing until a credential has been used to join, which is a separate
/// fact and is reported separately.
///
/// The installer is fetched to a file first rather than fed straight into a shell, so what ran is
/// still on the machine to be looked at when something about it goes wrong.
final class InstallTailscaleClient extends ReversibleStep<bool> {
  /// Puts the client on the machine from [installerUrl].
  const InstallTailscaleClient({required this.installerUrl, required this.installerPath});

  /// Builds the step from what the program gave it.
  factory InstallTailscaleClient.fromArguments(Arguments arguments) => InstallTailscaleClient(
    installerUrl: arguments.text('installer_url'),
    installerPath: arguments.text('installer_path'),
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
  ];

  /// What the tool is called.
  static const String tool = 'tailscale';

  /// The service that runs from the moment the client is installed.
  static const String service = 'tailscaled';

  /// The installer its makers publish.
  final String installerUrl;

  /// Where the installer is put.
  final String installerPath;

  @override
  Future<CheckResult> check(StepContext context) async =>
      await EnsureToolPrerequisites.onPath(context, tool)
      ? const CheckResult.satisfied('$tool is on the path')
      : const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>['sh', installerPath]);

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
    await _mustRun(context, <String>['sh', installerPath]);
    await _mustRun(context, <String>['systemctl', 'enable', '--now', service]);
    context.log.info(
      '$tool is installed and $service is running. It belongs to no network until a join credential '
      'has been used — that is a separate fact from this one.',
    );
  }

  /// Whether the client is on the path already.
  ///
  /// The undo stops the service and removes the package. A machine that was already on a private
  /// network when this ran would be taken off it — the credential it joined with is not on the
  /// machine to join again.
  @override
  Future<bool> capture(StepContext context) => EnsureToolPrerequisites.onPath(context, tool);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(const Command('systemctl', <String>['disable', '--now', service]));
    await context.shell.run(
      const Command.detailed(
        'apt-get',
        arguments: <String>['remove', '--yes', tool],
        environment: EnsureToolPrerequisites.quiet,
      ),
    );
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
