import 'package:ansiwise_api/ansiwise_api.dart';
import 'assert_cli_tool_versions.dart';

/// Fetches the deployment tool at exactly the version this platform pins.
///
/// **The skip is decided on the version and never on the presence.** A binary that was on the
/// machine before this platform existed would otherwise be left where it is, then held against the
/// pin, and reported as wrong on every run with nothing in the run able to correct it. Deciding on
/// the version means an ordinary re-run corrects a machine that drifted, with nothing forced.
///
/// **Nothing here resolves a latest release.** Two machines set up a month apart used to get
/// different tools and neither could be built again.
final class InstallArgocdCli extends ReversibleStep<bool> {
  /// Fetches [version] into [path].
  const InstallArgocdCli({required this.version, required this.path});

  /// Builds the step from what the program gave it.
  factory InstallArgocdCli.fromArguments(Arguments arguments) =>
      InstallArgocdCli(version: arguments.text('version'), path: arguments.text('path'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'version',
      kind: ArgumentKind.text,
      describes: 'the version this platform pins, as platform/versions.yaml records it',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'where the tool goes',
      required: false,
      defaultValue: defaultPath,
    ),
  ];

  /// Where the tool goes.
  static const String defaultPath = '/usr/local/bin/argocd';

  /// What the tool is called.
  static const String tool = 'argocd';

  /// `0755` — a tool every account on the machine runs.
  static const int mode = 0x1ed;

  /// The version this platform pins.
  final String version;

  /// Where the tool goes.
  final String path;

  /// Where it is fetched from.
  String get url =>
      'https://github.com/argoproj/argo-cd/releases/download/$version/argocd-linux-amd64';

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
    await _mustRun(context, _fetch);
    await _mustRun(context, <String>['chmod', '755', path]);
  }

  /// Whether a tool is already at the path this fetches into.
  ///
  /// The skip is decided on the version, so this step also runs on a machine that carries the tool
  /// at another version — and there the fetch replaces a file rather than creating one. Deleting it
  /// at undo time would leave the machine without the tool it came with.
  @override
  Future<bool> capture(StepContext context) => context.files.exists(path);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.files.delete(path);
  }

  List<String> get _fetch => <String>[
    'curl',
    '--silent',
    '--show-error',
    '--fail',
    '--location',
    '--output',
    path,
    url,
  ];

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
