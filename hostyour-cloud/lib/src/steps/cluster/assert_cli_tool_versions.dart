import 'package:ansiwise_api/ansiwise_api.dart';
import 'ensure_tool_prerequisites.dart';

/// Holds every tool on the machine against the version this platform pins for it.
///
/// **This is the only thing binding the list of tools to the steps that install them.** Each tool is
/// fetched its own way — a release, a package manager, an installer somebody else wrote — so there
/// is no loop over the list that installs them. Without this a tool added to the list would simply
/// never be installed, and nothing would say so.
///
/// **Two of them can only be reported and never enforced, and that distinction is deliberate.** The
/// tool from the package manager and the one from its makers' own installer take no version at all,
/// so no re-run can reach a pinned value for them — failing there would make an install that can
/// never end green on a machine whose package manager carries another version. Being MISSING is
/// still a failure, for every tool without exception.
///
/// **Everything wrong is reported at once.** An operator told about one tool, who fixes it, runs
/// again and is then told about the next has paid for four runs to learn what one could have said.
final class AssertCliToolVersions extends ObservingStep {
  /// Holds each of [tools] — each written as its name, an equals sign and its pin — against the
  /// machine.
  const AssertCliToolVersions({required this.tools, required this.unpinnable});

  /// Builds the step from what the program gave it.
  factory AssertCliToolVersions.fromArguments(Arguments arguments) => AssertCliToolVersions(
    tools: arguments.textList('tools'),
    unpinnable: arguments.textList('unpinnable'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'tools',
      kind: ArgumentKind.textList,
      describes:
          'every tool this platform pins, each written as its name, an equals sign and the '
          'version platform/versions.yaml records',
    ),
    ArgumentSpec(
      name: 'unpinnable',
      kind: ArgumentKind.textList,
      describes:
          'the tools whose install path takes no version, so a difference is reported and '
          'never failed on — being missing still fails',
      required: false,
      defaultValue: <String>['jq', 'tailscale'],
    ),
  ];

  /// How each tool is asked what version it is, and how that answer is read.
  ///
  /// One entry per tool, because each of them answers differently and one of them answers with more
  /// than the version: its first line carries it and everything after that is something else. Every
  /// reader here returns the bare version and nothing else, because that is what the pins are held
  /// against.
  static const Map<String, List<String>> readers = <String, List<String>>{
    'argocd': <String>['version', '--client', '--short'],
    'vault': <String>['version'],
    'yq': <String>['--version'],
    'jq': <String>['--version'],
    'tailscale': <String>['version'],
  };

  /// Every tool and its pin.
  final List<String> tools;

  /// The tools whose version is reported rather than enforced.
  final List<String> unpinnable;

  /// [pin] without the shapes the release tags carry, so it can be held against what a tool answers.
  ///
  /// The tags are written the way each project writes them and the readers all answer with the bare
  /// number, so the shapes come off here rather than in five places.
  static String bare(String pin) {
    String value = pin.trim();
    for (final String prefix in <String>['v', 'jq-']) {
      if (value.startsWith(prefix)) {
        value = value.substring(prefix.length);
      }
    }
    return value;
  }

  /// The version [tool] answers with, or null when it is not on the machine.
  ///
  /// Shared with every step that fetches a pinned tool, because the version on the machine is what
  /// each of them decides its own skip on and a second reader would answer differently.
  static Future<String?> installedVersion(StepContext context, String tool) async {
    if (!await EnsureToolPrerequisites.onPath(context, tool)) {
      return null;
    }
    final List<String>? reader = readers[tool];
    if (reader == null) {
      return null;
    }
    final CommandResult answer = await context.shell.run(Command.observing(tool, reader));
    if (!answer.ok) {
      return null;
    }
    // The first line only. One of these prints the version and then the commit it was built from
    // and more besides, and every pin here is held against a bare version.
    final String first = answer.stdout.split('\n').first;
    final RegExpMatch? version = _version.firstMatch(first);
    return version?.group(0);
  }

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> problems = <String>[];
    final List<String> reported = <String>[];
    final List<String> right = <String>[];

    for (final String entry in tools) {
      final int equals = entry.indexOf('=');
      if (equals <= 0) {
        problems.add(
          '"$entry" does not name a tool and its pin — it reads as a name, an equals sign and a '
          'version, such as yq=v4.53.3',
        );
        continue;
      }
      final String tool = entry.substring(0, equals).trim();
      final String pin = entry.substring(equals + 1).trim();

      if (pin.isEmpty) {
        problems.add('$tool has no pinned version, and a pin that is not written is not a pin');
        continue;
      }
      if (readers[tool] == null) {
        problems.add('nothing here knows how to ask $tool what version it is');
        continue;
      }

      final String? installed = await installedVersion(context, tool);
      if (installed == null) {
        problems.add('$tool is not on this machine');
        continue;
      }
      if (installed == bare(pin)) {
        right.add('$tool $installed');
        continue;
      }
      if (unpinnable.contains(tool)) {
        reported.add('$tool is at $installed and this platform pins $pin');
        continue;
      }
      problems.add(
        '$tool is at $installed and this platform pins $pin — an ordinary re-run of this program '
        'fetches the pinned one',
      );
    }

    for (final String difference in reported) {
      context.log.warn(
        '$difference. Its install path takes no version, so no run can reach the pin and this is '
        'reported rather than failed on.',
      );
    }
    if (problems.isNotEmpty) {
      return CheckResult.blocked(problems.join('; '));
    }
    return CheckResult.satisfied('every pinned tool is at its pin: ${right.join(', ')}');
  }

  /// The first thing on a line that looks like a version.
  static final RegExp _version = RegExp(r'\d+\.\d+(\.\d+)?');
}
