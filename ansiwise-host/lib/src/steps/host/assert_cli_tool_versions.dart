import 'package:ansiwise_api/ansiwise_api.dart';
import 'ensure_tool_prerequisites.dart';

/// Holds every tool on the machine against the version the program pins for it.
///
/// **This is the only thing binding the list of tools to the steps that install them.** Each tool
/// arrives its own way — most of them as a release fetched at a pin, one out of the package manager,
/// one out of an installer somebody else wrote — and each of those is a row of its own in the
/// program file, so there is no loop over this list that installs them. Without this a tool added to
/// the list would simply never be installed, and nothing would say so.
///
/// **Two of them can only be reported and never enforced, and that distinction is deliberate.** The
/// tool from the package manager and the one from its makers' own installer take no version at all.
/// The package manager carries exactly ONE of the tool it ships, and the installer fetches whatever
/// its makers publish on the day, so no re-run of this program can reach a different version for
/// either of them — and failing on the version they do carry would make an install that can never
/// end green on a machine whose package manager disagrees with the pin. What is left is worth
/// having: the difference is reported, so an operator who cares can act on it. Being MISSING is
/// still a failure, for every tool without exception.
///
/// **Their presence is what decides whether to install them, and their version is only reported.**
/// That is the other half of the same fact, and it is why the two steps that put those two on the
/// machine take no version argument at all: there is no version they could be given that would
/// change what they fetch.
///
/// **Everything wrong is reported at once.** An operator told about one tool, who fixes it, runs
/// again and is then told about the next has paid for four runs to learn what one could have said.
final class AssertCliToolVersions extends ObservingStep {
  /// Holds each of [tools] — each written as its name, an equals sign and its pin — against the
  /// machine, asking each one its version the way [versionCommands] states.
  const AssertCliToolVersions({
    required this.tools,
    required this.unpinnable,
    required this.versionCommands,
    required this.pinPrefixes,
  });

  /// Builds the step from what the program gave it.
  factory AssertCliToolVersions.fromArguments(Arguments arguments) => AssertCliToolVersions(
    tools: arguments.textList('tools'),
    unpinnable: arguments.textList('unpinnable'),
    versionCommands: arguments.textList('version_commands'),
    pinPrefixes: arguments.textList('pin_prefixes'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'tools',
      kind: ArgumentKind.textList,
      describes:
          'every tool the program pins, each written as its name, an equals sign and its '
          'pinned version',
    ),
    // No default: which tools arrive without a version is decided by which install path the
    // program chose for each, so the program row states it.
    ArgumentSpec(
      name: 'unpinnable',
      kind: ArgumentKind.textList,
      describes:
          'the tools whose install path takes no version, so a difference is reported and '
          'never failed on — being missing still fails',
    ),
    // No default, and no table of tools in this file. Each of these tools answers differently, and
    // which tools a run holds is decided by the program that pins them — so a map written here
    // would be the tool list of whichever product was in front of the author.
    ArgumentSpec(
      name: 'version_commands',
      kind: ArgumentKind.textList,
      describes:
          'how each tool is asked what version it is, each written as its name, an equals sign '
          'and the arguments it is run with, such as yq=--version — a tool named in tools with '
          'nothing here is refused, because its version could not be read',
    ),
    // No default here either, and for the same reason as the table above: a release tag is written
    // the way its own project writes it, so which shapes a run has to take off is decided by which
    // tools the program pins. A list written here would be the tag shapes of whichever product was
    // in front of the author.
    ArgumentSpec(
      name: 'pin_prefixes',
      kind: ArgumentKind.textList,
      describes:
          'the shapes a release tag is written with, taken off a pin before it is held against what '
          'a tool answers — such as v for v4.53.3. At most one comes off any pin, so a tag that '
          'begins with one of these and holds another is left as it stands',
    ),
  ];

  /// Every tool and its pin.
  final List<String> tools;

  /// The tools whose version is reported rather than enforced.
  final List<String> unpinnable;

  /// How each tool is asked what version it is, each written as its name, an equals sign and the
  /// arguments it is run with.
  final List<String> versionCommands;

  /// The shapes a release tag is written with, taken off a pin before it is compared.
  final List<String> pinPrefixes;

  /// [versionCommands] read as the arguments each tool is asked its version with, keyed by tool.
  ///
  /// An entry that does not read as a name, an equals sign and at least one argument is left out
  /// rather than guessed at, so the tool it was meant for meets the same refusal as a tool nobody
  /// wrote one for at all.
  Map<String, List<String>> get readers {
    final Map<String, List<String>> byTool = <String, List<String>>{};
    for (final String entry in versionCommands) {
      final int equals = entry.indexOf('=');
      if (equals <= 0) {
        continue;
      }
      final List<String> argv = <String>[
        for (final String word in entry.substring(equals + 1).split(' '))
          if (word.trim().isNotEmpty) word.trim(),
      ];
      if (argv.isEmpty) {
        continue;
      }
      byTool[entry.substring(0, equals).trim()] = argv;
    }
    return byTool;
  }

  /// [pin] without the shape its release tag carries, so it can be held against what a tool answers.
  ///
  /// The tags are written the way each project writes them and the readers all answer with the bare
  /// number, so the shape comes off here rather than in every place that holds a pin against one.
  ///
  /// **At most ONE shape comes off, and that is the whole of the rule.** A tag carries one shape,
  /// so stripping every match in turn eats into the version itself the moment two of the given
  /// shapes overlap: with `v` and `jq-` both given, `vjq-1.7` loses both and is compared as `1.7`
  /// against a tool that answers something else entirely — a pin silently held against the wrong
  /// number. The longest match wins, so a shape that begins with another one is not cut short.
  static String bare(String pin, List<String> prefixes) {
    final String value = pin.trim();
    String longest = '';
    for (final String prefix in prefixes) {
      if (prefix.isNotEmpty && value.startsWith(prefix) && prefix.length > longest.length) {
        longest = prefix;
      }
    }
    return value.substring(longest.length);
  }

  /// The version [tool] answers with when it is run with [versionCommand], or null when it is not
  /// on the machine or would not answer.
  ///
  /// Shared with the step that fetches a pinned release, because the version on the machine is what
  /// it decides its own skip on and a second way of reading it here would answer differently.
  static Future<String?> installedVersion(
    StepContext context,
    String tool,
    List<String> versionCommand,
  ) async {
    if (!await EnsureToolPrerequisites.onPath(context, tool)) {
      return null;
    }
    final CommandResult answer = await context.shell.run(Command.observing(tool, versionCommand));
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
    final Map<String, List<String>> readers = this.readers;

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
      final List<String>? reader = readers[tool];
      if (reader == null) {
        problems.add('nothing was given to ask $tool what version it is');
        continue;
      }

      final String? installed = await installedVersion(context, tool, reader);
      if (installed == null) {
        problems.add('$tool is not on this machine');
        continue;
      }
      if (installed == bare(pin, pinPrefixes)) {
        right.add('$tool $installed');
        continue;
      }
      if (unpinnable.contains(tool)) {
        reported.add('$tool is at $installed and the program pins $pin');
        continue;
      }
      problems.add(
        '$tool is at $installed and the program pins $pin — an ordinary re-run of this program '
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
