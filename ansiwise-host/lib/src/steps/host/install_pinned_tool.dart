import 'package:ansiwise_api/ansiwise_api.dart';
import 'assert_cli_tool_versions.dart';

/// Fetches one tool's released binary at exactly the version the program pins, and puts it where
/// the machine looks for commands.
///
/// **The skip is decided on the version and never on the presence.** A binary that was on the
/// machine before this program first ran would otherwise be left where it is, then held against the
/// pin, and reported as wrong on every run with nothing in the run able to correct it. Deciding on
/// the version means an ordinary re-run corrects a machine that drifted, with nothing forced.
///
/// **Nothing here resolves a latest release.** [url] carries the pin in a marked slot instead of a
/// version of its own, so what is fetched and what the machine is held against are one value that
/// cannot come apart. Two machines set up a month apart used to get different tools and neither
/// could be built again.
///
/// **A release that arrives packed is unpacked into place; one that IS the binary is fetched
/// straight to where it goes.** [archive] says which of the two this is, and it is also where the
/// packed copy is put while it is being unpacked. That copy is removed afterwards whether the
/// unpacking worked or not — a half-finished download left there is what the next run would unpack.
///
/// **A packed release has to hold exactly one file, named for the tool.** The unpacking writes
/// everything the archive holds into [directory]; this step never reads what came out of it and
/// never names it. So a second file in the archive lands on the machine beside the tool, over
/// whatever stood there under that name, with nothing in the record saying it arrived. Whoever
/// writes an archive into a program row is the one who holds this, and the [archive] argument says
/// so where that row is written.
///
/// **It cannot be taken back, although a run that only created the file could be.** The fetch
/// writes over whatever [path] held, and keeping the replaced binary would mean copying it aside
/// before the apply — a change to the machine made by the capture, which is the one part of a
/// reversible step required to change nothing, and a copy nothing would ever clear away again,
/// because a step is told to undo and is never told the run succeeded. Which machine a run meets is
/// decided by the machine and not the program, and this step exists for the one carrying another
/// version. A step declares one kind for every machine, so it declares the kind that holds for the
/// worse of them. The cost: a run that only created a file is announced as a point of no return it
/// was not; the other way round would be a step promising to put back a binary it never kept, which
/// is the failure that matters.
final class InstallPinnedTool extends IrreversibleStep {
  /// Fetches [tool] at [version] from [url] into [directory], out of [archive] where there is one,
  /// and reads what is on the machine by running the tool with [versionCommand].
  const InstallPinnedTool({
    required this.tool,
    required this.version,
    required this.url,
    required this.directory,
    required this.archive,
    required this.versionCommand,
    required this.pinPrefixes,
  });

  /// Builds the step from what the program gave it.
  factory InstallPinnedTool.fromArguments(Arguments arguments) => InstallPinnedTool(
    tool: arguments.text('tool'),
    version: arguments.text('version'),
    url: arguments.text('url'),
    directory: arguments.text('directory'),
    archive: arguments.optionalText('archive'),
    versionCommand: arguments.textList('version_command'),
    pinPrefixes: arguments.textList('pin_prefixes'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'tool',
      kind: ArgumentKind.text,
      describes:
          'what the tool is called — the command it is started as, and the name it goes on the '
          'machine under',
    ),
    ArgumentSpec(
      name: 'version',
      kind: ArgumentKind.text,
      describes: 'the version the program pins for this tool',
    ),
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      describes:
          'where the release is fetched from, written with $versionPlaceholder where the pin '
          'belongs and $bareVersionPlaceholder where it belongs without the shape its tag carries',
    ),
    ArgumentSpec(
      name: 'directory',
      kind: ArgumentKind.text,
      describes: 'where the tool goes',
      required: false,
      defaultValue: defaultDirectory,
    ),
    ArgumentSpec(
      name: 'archive',
      kind: ArgumentKind.text,
      describes:
          'where the packed copy is put while it is being unpacked, for a release that arrives as '
          'a zip — a release that is the binary itself names none. The archive has to hold exactly '
          'one file, named for the tool: everything in it is unpacked into the directory, and '
          'anything else it holds lands on the machine with nothing in the record naming it',
      required: false,
    ),
    // No default, and no table of tools in this package. How a tool answers what version it is is a
    // fact of that tool, so the row that names the tool is what states it.
    ArgumentSpec(
      name: 'version_command',
      kind: ArgumentKind.textList,
      describes:
          'the arguments this tool is run with to ask it what version it is, such as --version — '
          'the skip is decided on the version, so a tool nothing can ask is refused rather than '
          'fetched again on every run',
    ),
    // No default: which tag shapes are in play is decided by which tools the program pins, and the
    // same list has to reach the step that holds every tool against its pin — so it stands once in
    // the program rather than twice in this package.
    ArgumentSpec(
      name: 'pin_prefixes',
      kind: ArgumentKind.textList,
      describes:
          'the shapes a release tag is written with, taken off the pin where the url asks for it '
          "without one and before the tool's own answer is compared — such as v for v4.53.3",
    ),
  ];

  /// Where the tool goes.
  static const String defaultDirectory = '/usr/local/bin';

  /// The text a program file writes in the url where the pin belongs.
  static const String versionPlaceholder = '<version>';

  /// The text a program file writes in the url where the pin belongs without the shape its tag
  /// carries.
  ///
  /// Two slots rather than one, because the projects disagree about the shape while the program
  /// pins one value. A release tag is written the way its own project writes it, and one of these
  /// download paths spells the version without the leading letter that tag has — so the pin is
  /// written once, in the shape the pins are kept in, and the url says which shape it needs.
  static const String bareVersionPlaceholder = '<bare-version>';

  /// What the tool is called.
  final String tool;

  /// The version the program pins.
  final String version;

  /// Where the release is fetched from, with the pin still in its marked slots.
  final String url;

  /// Where the tool goes.
  final String directory;

  /// Where the packed copy is put while it is being unpacked, or null where the release is the
  /// binary itself.
  final String? archive;

  /// What the tool is run with to ask it what version it is.
  final List<String> versionCommand;

  /// The shapes a release tag is written with, taken off the pin.
  final List<String> pinPrefixes;

  /// Where the tool ends up.
  ///
  /// The name a command is started as and the name of the file it is started from are the same
  /// thing here, which is what lets a fetch and an unpacking land in the same place: `curl` is told
  /// this path, and `unzip` is told the directory and writes the tool under its own name into it.
  String get path => '$directory/$tool';

  /// Where it is fetched from, with the pin in it.
  String get fetchedFrom => filledSlots(url, <String, String>{
    'version': version,
    'bare-version': AssertCliToolVersions.bare(version, pinPrefixes),
  });

  /// Why this cannot be taken back, written for the machine where it costs something.
  ///
  /// It is stated as what the step MAY do rather than as what it will: this step runs on a machine
  /// that carries no such tool as readily as on one carrying another version, and on the first it
  /// creates a file and replaces nothing. A reason claiming a binary of theirs is going away would
  /// be false there, on the one surface an operator reads before deciding — the point of no return.
  @override
  String get irreversibleReason =>
      'the release is written straight to $path, and where something already stood there it is '
      'written over with nothing on this machine keeping a copy of it — and where the release '
      'arrives packed, everything the archive holds is unpacked into $directory over whatever stood '
      'there under those names';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (version.trim().isEmpty) {
      return CheckResult.blocked(
        'no version was given for $tool, and this fetches a pinned release rather than whatever is '
        'current',
      );
    }
    if (!url.contains(versionPlaceholder) && !url.contains(bareVersionPlaceholder)) {
      return CheckResult.blocked(
        'the url for $tool names neither $versionPlaceholder nor $bareVersionPlaceholder, so what '
        'is fetched and what the pin says are two values that can drift apart with nothing saying '
        'so',
      );
    }
    if (leftoverSlotIn(fetchedFrom) case final String left) {
      return CheckResult.blocked(
        'the url for $tool still carries $left once the pin filled $versionPlaceholder and '
        '$bareVersionPlaceholder — nothing else fills a slot here, and the fetch would send the '
        'text as it stands',
      );
    }
    if (versionCommand.isEmpty) {
      return CheckResult.blocked(
        'nothing was given to ask $tool what version it is, and this step decides its skip on the '
        'version — so it would fetch the release again on every run',
      );
    }
    final String? installed = await AssertCliToolVersions.installedVersion(
      context,
      tool,
      versionCommand,
    );
    if (installed == AssertCliToolVersions.bare(version, pinPrefixes)) {
      return CheckResult.satisfied('$tool is at $installed');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_fetch);

  @override
  Future<void> apply(StepContext context) async {
    final String? packed = archive;
    if (packed == null) {
      await _mustRun(context, _fetch);
      // A file curl wrote carries no execute bit, and one unzip wrote carries the mode the archive
      // recorded — so this is on the unpacked path only. 755: a tool every account on the machine
      // runs.
      await _mustRun(context, <String>['chmod', '755', path]);
      return;
    }
    try {
      await _mustRun(context, _fetch);
      await _mustRun(context, <String>['unzip', '-o', '-d', directory, packed]);
    } finally {
      // On both paths. A half-finished download left here is what a later run would unpack, and the
      // tool that came out of it would be a tool nobody could name a version for.
      await context.files.delete(packed);
    }
  }

  List<String> get _fetch => <String>[
    'curl',
    '--silent',
    '--show-error',
    '--fail',
    '--location',
    '--output',
    archive ?? path,
    fetchedFrom,
  ];

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
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
