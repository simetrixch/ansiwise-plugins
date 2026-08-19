import 'package:ansiwise_core/ansiwise_core.dart';

/// Writes one service unit for the service manager, and tells the manager it exists.
///
/// **The unit is the template's, the command is the row's, and the two meet here.** What a service
/// IS — its dependencies, its restart policy, how its processes are killed — is the unit file, and
/// that file travels beside the programs as a template. What the service RUNS is a fact the same
/// program establishes on other rows: the row that fetched the binary says where it stands, the row
/// that placed a checkout says where that is, and the command written on THIS row is where a reader
/// sees all of them agree. A command composed inside the template would put those paths in a second
/// place, and the two would drift with nothing reporting it.
///
/// **`keeps_detached_children` is the property this step can refuse a unit over, and the refusal is
/// about the service manager, not about any product.** The manager's default way of stopping a unit
/// is to kill the unit's whole control group, and a restart is a stop. A process a service starts
/// DETACHED gets a new session — not a new control group — so the default takes every such child
/// with the restart. A service whose reason to exist is that its children outlive it is therefore
/// broken by its own unit file unless that file says `KillMode=process`, and nothing else on the
/// machine ever reports why the children vanished. A row that declares the flag gets a unit refused
/// until the rendered text carries that line.
///
/// **The manager is told after every write.** It reads its directory once at start-up and once when
/// asked; a file written without telling it is a service that does not exist as far as it is
/// concerned.
final class WriteServiceUnit extends ReversibleStep<String?> with FileStep, TemplateStep {
  /// Writes the unit at [path], starting the command the row states.
  const WriteServiceUnit({
    required this.templatePath,
    required this.path,
    required this.command,
    required this.workingDirectory,
    required this.keepsDetachedChildren,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory WriteServiceUnit.fromArguments(Arguments arguments) => WriteServiceUnit(
    templatePath: arguments.text('template'),
    path: arguments.text('path'),
    command: arguments.textList('command'),
    workingDirectory: arguments.optionalText('working_directory'),
    keepsDetachedChildren:
        arguments.has('keeps_detached_children') && arguments.flag('keeps_detached_children'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the unit file as text, beside the programs of this installation, with the slot '
          '<command> where the started command belongs and <working-directory> where the directory '
          'it starts in belongs, if the unit names one',
    ),
    // No defaults at all. The unit's path is its name — the service manager names every unit under
    // its directory by base name — and the command is what the other rows of the same program put
    // on the machine, so a default here would start a service nobody installed.
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the unit file, whose base name is the name the service is started under',
    ),
    ArgumentSpec(
      name: 'command',
      kind: ArgumentKind.textList,
      describes:
          'the command the service runs, the executable first and each argument as its own entry. '
          'It is written into the unit joined by single spaces, so no entry may carry a space: the '
          'service manager reads the line under quoting rules of its own that this step does not '
          'restate',
    ),
    ArgumentSpec(
      name: 'working_directory',
      kind: ArgumentKind.text,
      describes:
          'the directory the service starts in, for a template that names the '
          '<working-directory> slot. Leave it off where the template names none',
      required: false,
    ),
    ArgumentSpec(
      name: 'keeps_detached_children',
      kind: ArgumentKind.flag,
      describes:
          'whether processes this service starts detached must outlive a restart of the unit. The '
          "service manager's default kill mode takes the unit's whole control group — a detached "
          'child gets a new session, not a new control group, so it goes with every restart. With '
          'this flag the rendered unit is refused unless it says KillMode=process',
      required: false,
    ),
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row. A step deciding it for every caller
    // would be a tool package knowing something about the product that pointed it.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so reading and writing it need elevation. Leave it '
          'off for a path this account owns',
      required: false,
    ),
  ];

  /// `0644` — a unit file the service manager reads.
  static const int fileMode = 0x1a4;

  /// The line a unit that keeps its detached children alive has to carry.
  ///
  /// The service manager's own vocabulary: `process` kills the main process alone, where the
  /// default kills the control group and everything in it.
  static const String keepsChildrenLine = 'KillMode=process';

  /// Whether the file belongs to root, so every read and write of it is elevated.
  @override
  final bool elevated;

  @override
  final String templatePath;

  /// The unit file's path.
  final String path;

  /// The command the service runs, the executable first.
  final List<String> command;

  /// The directory the service starts in, or null where the template names none.
  final String? workingDirectory;

  /// Whether processes this service starts detached must outlive a restart of the unit.
  final bool keepsDetachedChildren;

  /// The name the service is started under: the file's own base name, which is how the service
  /// manager names every unit under its directory. One value, so the file this writes and the
  /// service the undo stops cannot come apart.
  String get unitName => path.split('/').last;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => fileMode;

  @override
  Future<FileContent> contentFor(StepContext context) async =>
      FileContent.text(await renderedWith(context, values));

  /// The gate on the rendered text, in front of the ordinary file comparison.
  ///
  /// It reads the RENDERED unit and not the template, because the property has to hold for the
  /// file that lands on the machine — a template could carry the line inside a slot's value or
  /// lose it to a line an optional slot dropped, and either way the file is what the service
  /// manager reads.
  @override
  Future<CheckResult> check(StepContext context) async {
    if (keepsDetachedChildren) {
      final String rendered = await renderedWith(context, values);
      final bool carries = rendered
          .split('\n')
          .any((String line) => line.trim() == keepsChildrenLine);
      if (!carries) {
        return CheckResult.blocked(
          'this row says processes the service starts detached must outlive a restart of the '
          'unit, and the unit rendered from $templatePath does not say $keepsChildrenLine — the '
          "service manager's default kill mode takes the unit's whole control group, and a "
          'detached child gets a new session, not a new control group, so every restart would '
          'take the children with it',
        );
      }
    }
    return super.check(context);
  }

  @override
  Future<void> apply(StepContext context) async {
    await super.apply(context);
    // The service manager reads its directory once at start-up and once when it is told to. A file
    // written without telling it is a service that does not exist as far as it is concerned.
    await context.shell.run(
      const Command.detailed('systemctl', arguments: <String>['daemon-reload'], elevated: true),
    );
  }

  /// What the unit file held before, or null when it was not there.
  ///
  /// A machine that arrived with a unit of this name gets its file back rather than losing it,
  /// and the service manager is told to read the directory again either way.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    // Stopped first, so the unwinding of a failed run does not leave a service running out of a
    // file this undo is about to take away or rewrite.
    await context.shell.run(
      Command.detailed(
        'systemctl',
        arguments: <String>['disable', '--now', unitName],
        elevated: true,
      ),
    );
    if (captured == null) {
      await context.files.delete(path, elevated: elevated);
    } else {
      await context.files.write(path, captured, mode: mode, elevated: elevated);
    }
    await context.shell.run(
      const Command.detailed('systemctl', arguments: <String>['daemon-reload'], elevated: true),
    );
  }

  /// What goes in each slot of the unit file.
  ///
  /// The command joined by single spaces, which is why no entry of it may carry one: the service
  /// manager reads the line under quoting rules of its own, and this step restating them would be a
  /// second grammar that drifts from the real one.
  Map<String, String> get values => <String, String>{
    'command': command.join(' '),
    if (workingDirectory case final String directory) 'working-directory': directory,
  };
}
