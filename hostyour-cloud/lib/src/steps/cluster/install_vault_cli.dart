import 'package:ansiwise_api/ansiwise_api.dart';
import 'assert_cli_tool_versions.dart';

/// Fetches the secret-store tool at exactly the version this platform pins.
///
/// It arrives packed, so it is unpacked into place and the packed copy is removed afterwards —
/// whether the unpacking worked or not, because a half-finished download left in the temporary
/// directory is what the next run would find and unpack.
final class InstallVaultCli extends ReversibleStep<bool> {
  /// Fetches [version] into [directory].
  const InstallVaultCli({required this.version, required this.directory});

  /// Builds the step from what the program gave it.
  factory InstallVaultCli.fromArguments(Arguments arguments) =>
      InstallVaultCli(version: arguments.text('version'), directory: arguments.text('directory'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'version',
      kind: ArgumentKind.text,
      describes: 'the version this platform pins, as platform/versions.yaml records it',
    ),
    ArgumentSpec(
      name: 'directory',
      kind: ArgumentKind.text,
      describes: 'where the tool goes',
      required: false,
      defaultValue: defaultDirectory,
    ),
  ];

  /// Where the tool goes.
  static const String defaultDirectory = '/usr/local/bin';

  /// What the tool is called.
  static const String tool = 'vault';

  /// Where the packed copy is put while it is being unpacked.
  static const String archive = '/tmp/vault.zip';

  /// The version this platform pins.
  final String version;

  /// Where the tool goes.
  final String directory;

  /// Where it is fetched from.
  String get url {
    final String bare = AssertCliToolVersions.bare(version);
    return 'https://releases.hashicorp.com/vault/$bare/vault_${bare}_linux_amd64.zip';
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (version.trim().isEmpty) {
      return const CheckResult.blocked(
        'no version was given for $tool, and this fetches a pinned release rather than whatever is '
        'current',
      );
    }
    final String? installed = await AssertCliToolVersions.installedVersion(context, tool);
    if (installed == AssertCliToolVersions.bare(version)) {
      return CheckResult.satisfied('$tool is at $installed');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_fetch);

  @override
  Future<void> apply(StepContext context) async {
    try {
      await _mustRun(context, _fetch);
      await _mustRun(context, <String>['unzip', '-o', '-d', directory, archive]);
    } finally {
      // On both paths. A half-finished download left here is what a later run would unpack, and the
      // tool that came out of it would be a tool nobody could name a version for.
      await context.files.delete(archive);
    }
  }

  /// Whether the tool is already in the directory this unpacks into.
  ///
  /// The skip is decided on the version, so the unpacking replaces a tool that is there at another
  /// version. Deleting it at undo time would take away the one the machine came with.
  @override
  Future<bool> capture(StepContext context) => context.files.exists('$directory/$tool');

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete('$directory/$tool');
  }

  List<String> get _fetch => <String>[
    'curl',
    '--silent',
    '--show-error',
    '--fail',
    '--location',
    '--output',
    archive,
    url,
  ];

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
