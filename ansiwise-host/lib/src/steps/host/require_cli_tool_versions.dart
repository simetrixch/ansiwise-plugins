import 'package:ansiwise_core/ansiwise_core.dart';
import 'install_tool_prerequisites.dart';

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
final class RequireCliToolVersions extends ObservingStep {
  /// Holds each of [tools] — each written as its name, an equals sign and its pin — against the
  /// machine, asking each one its version the way [versionCommands] states.
  const RequireCliToolVersions({
    required this.tools,
    required this.unpinnable,
    required this.versionCommands,
    required this.pinPrefixes,
  });

  /// Builds the step from what the program gave it.
  factory RequireCliToolVersions.fromArguments(Arguments arguments) => RequireCliToolVersions(
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
  /// **THREE STATES COME BACK WITHOUT A VERSION AND THEY ARE NOT ONE THING.** A tool that is not on
  /// the machine, one that is there and would not answer, and one that answered something no shape
  /// could read are three different situations for whoever reads the report — and told the first
  /// when it is the third, they go and place a binary that is already standing there.
  ///
  /// The third is not hypothetical: a binary built outside a release answers a word rather than a
  /// number, deliberately, so that nothing compares it to a pin. A developer's build on a machine
  /// is exactly that.
  static Future<({String? version, String problem})> installedVersion(
    StepContext context,
    String tool,
    List<String> versionCommand,
  ) async {
    if (!await InstallToolPrerequisites.onPath(context, tool)) {
      return (version: null, problem: '$tool is not on this machine');
    }
    final CommandResult answer = await context.shell.run(
      Command.observing(tool, arguments: versionCommand),
    );
    if (!answer.ok) {
      final String said = answer.stderr.trim();
      return (
        version: null,
        problem:
            '$tool is on this machine and would not say what version it is: '
            '${versionCommand.join(' ')} '
            '${said.isEmpty ? 'failed and said nothing' : 'said $said'}',
      );
    }
    // The first line only. One of these prints the version and then the commit it was built from
    // and more besides, and every pin here is held against a bare version.
    final String first = answer.stdout.split('\n').first;
    final String? read = versionIn(first);
    if (read == null) {
      return (
        version: null,
        problem:
            '$tool answered "${first.trim()}", and nothing on that line is shaped like a version. '
            'A binary built outside a release answers a word rather than a number on purpose, so '
            'that nothing compares it to a pin — which is what this reads like',
      );
    }
    return (version: read, problem: '');
  }

  /// The version [said] carries, or null where nothing on it is shaped like one.
  ///
  /// Both steps that hold a machine against a pin read a version through here, so what a version
  /// looks like is spelled once rather than twice. Two spellings that drift apart give a tool read
  /// one way by the step that fetches it and another way by the step that holds every tool against
  /// its pin: the fetch never skips and the assertion reports the machine right, and each run
  /// quietly fetches the release again.
  ///
  /// **The FULLER shape is tried first, and that order is the whole of it.** A tool that stamps its
  /// binaries with a release tag answers `<major>.<minor>.<patch>-<channel>-<ts14>`, so what it says
  /// BEGINS with something the plain numbered shape matches: a reader that tries the shorter one
  /// first stops at `0.1.0` inside `0.1.0-alpha-20260822223803` and answers a version the tool never
  /// said. That answer is then held against a pin that is still whole, so it never matches, and the
  /// release is fetched again on every run — silently, because each fetch succeeds. The shorter
  /// shape is the bare number the rest of the pinned tools answer, and it is reached by a line the
  /// fuller one does not fit.
  ///
  /// **The shape decides before the position on the line does.** Where one line carries both — a
  /// release tag with some other number in front of it — the release tag is what comes back, and
  /// not whichever stands first. A tool answers ONE version, which is why the readers take the first
  /// line at all, so such a line is a shape nobody has produced — while the other order is the
  /// defect above on every release-tagged tool there is.
  static String? versionIn(String said) {
    for (final RegExp shape in _versionShapes) {
      final RegExpMatch? found = shape.firstMatch(said);
      if (found != null) {
        return found.group(0);
      }
    }
    return null;
  }

  @override
  bool get restsOnAnEarlierStep => true;

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

      final ({String? version, String problem}) reading = await installedVersion(
        context,
        tool,
        reader,
      );
      final String? installed = reading.version;
      if (installed == null) {
        problems.add(reading.problem);
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

  /// The shapes a tool writes a version in, FULLEST FIRST — [versionIn] states why the order is the
  /// whole of it.
  ///
  /// The first is the release-tag grammar a stamped binary answers with,
  /// `<major>.<minor>.<patch>-<channel>-<ts14>`, where ts14 is a UTC `yyyyMMddHHmmss`. The authority
  /// for it is the anchored form that also names its channels by hand, and it lives beside the
  /// pipeline that mints the tags, in a repository this package may not name — a tool package names
  /// no product built on its tools, which is why the grammar is described here rather than cited.
  /// That form JUDGES whether a tag is well formed; this one only has to FIND a tag inside a line
  /// some tool printed, so it is deliberately the looser of the two. A channel word added later is
  /// still read whole here, where a stricter copy would fall through to the second shape and take
  /// three numbers out of a tag it did not recognise — the exact failure this list is ordered to
  /// prevent, arrived at from the other side.
  ///
  /// The second is the bare number every other pinned tool answers with, two parts or three.
  static final List<RegExp> _versionShapes = <RegExp>[
    RegExp(r'\d+\.\d+\.\d+-[A-Za-z]+-\d{14}'),
    RegExp(r'\d+\.\d+(\.\d+)?'),
  ];
}
