import 'package:ansiwise_core/ansiwise_core.dart';
import 'measure_public_nic.dart';
import 'quoted_slot.dart';

/// Writes the service that runs the steering script, and takes it away again when it is stopped.
///
/// **What the script installs is kernel state, and kernel state does not survive.** A restart, or
/// anything that empties the machine's rule set, takes both the marking rules and the rule keyed on
/// the mark away — and nothing about the files on disk says so. A service that runs the script after
/// the network is up is what puts them back.
///
/// **Stopping the service is what removes them, which is why it says how.** Deleting the files does
/// not: the rules are already in the kernel. So the service carries the two commands that take them
/// out, and stopping it is the first act of any teardown.
final class WritePublicSrcRoutingUnit extends ReversibleStep<String?> with FileStep, TemplateStep {
  /// Writes the service at [path], running the script at [scriptPath].
  const WritePublicSrcRoutingUnit({
    required this.templatePath,
    required this.path,
    required this.scriptPath,
    required this.tableName,
    required this.mark,
    required this.table,
    required this.priority,
    this.elevated = false,
    this.escaping,
  });

  /// Builds the step from what the program gave it.
  factory WritePublicSrcRoutingUnit.fromArguments(Arguments arguments) => WritePublicSrcRoutingUnit(
    templatePath: arguments.text('template'),
    path: arguments.text('path'),
    scriptPath: arguments.text('script_path'),
    tableName: arguments.text('table_name'),
    mark: arguments.text('mark'),
    table: arguments.integer('table'),
    priority: arguments.integer('priority'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
    escaping: Escaping.named(arguments.optionalText('escaping')),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the service file as text, with a marked slot where each value this run holds belongs — '
          '<script-path>, <table-name>, <mark>, <table> and <priority>',
    ),
    // No defaults at all. The paths and the table name are the installation's own, and the mark,
    // the table and the number are what the steps that installed them chose against THIS machine —
    // the stopping commands in this file take exactly those out of the kernel, so a default here
    // would write a service that removes a rule nobody installed and leaves the real one behind.
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the service file, whose base name is the name the service is started under',
    ),
    ArgumentSpec(
      name: 'script_path',
      kind: ArgumentKind.text,
      describes: 'the script the service runs',
    ),
    ArgumentSpec(
      name: 'table_name',
      kind: ArgumentKind.text,
      describes: 'the nft table the stopping commands destroy — the one the rules file defines',
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes: 'the mark the rule is keyed on, as the rules the script loads put it on',
    ),
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes:
          'the routing table the marked replies are steered into, as the drop-in that holds the '
          'public gateway numbers it',
    ),
    ArgumentSpec(
      name: 'priority',
      kind: ArgumentKind.integer,
      describes: 'the number the rule keyed on the mark is installed at, as the script installs it',
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
    ArgumentSpec(
      name: 'escaping',
      kind: ArgumentKind.text,
      describes:
          'how this file writes a quote character that is part of a value, where a slot stands '
          'inside quoting — "doubled" writes it twice, as YAML single quoting and SQL do, and '
          '"backslash" puts one in front, as JSON and YAML double quoting do. Leave it off and a '
          'value that would close the quoting its slot stands inside is refused by name instead',
      required: false,
    ),
  ];

  /// `0644` — a service file the service manager reads.
  static const int fileMode = 0x1a4;

  /// The service file as text, with a marked slot where each value belongs.

  /// Whether the file belongs to root, so every read and write of it is elevated.
  @override
  final bool elevated;
  @override
  final String templatePath;

  /// The service file's path.
  final String path;

  /// The script it runs.
  final String scriptPath;

  /// The nft table the stopping commands destroy.
  final String tableName;

  /// The name the service is started under: the file's own base name, which is how the service
  /// manager names every unit under its directory. One value, so the file this writes and the
  /// service the undo stops cannot come apart.
  String get unitName => path.split('/').last;

  /// The mark the rule is keyed on.
  final String mark;

  /// The table the marked replies go into.
  final int table;

  /// The number the rule sits at.
  final int priority;

  /// How this file writes a quote character that is part of a value, where a slot stands inside
  /// quoting, or null where the row says nothing and such a value is refused.
  final Escaping? escaping;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => fileMode;

  /// The service, on a machine that steers anything at all.
  ///
  /// A machine with no public interface of its own has no rule to install, so there is no service
  /// to run the script that installs it.
  @override
  Future<FileContent> contentFor(StepContext context) async =>
      await MeasurePublicNic.measure(context) == null
      ? const FileContent.nothing(
          'nothing is steered on this machine, so there is no service to install',
        )
      : FileContent.text(await renderedKeepingQuoting(context, values, escaping: escaping));

  @override
  Future<void> apply(StepContext context) async {
    await super.apply(context);
    // The service manager reads its directory once at start-up and once when it is told to. A file
    // written without telling it is a service that does not exist as far as it is concerned.
    await context.shell.run(
      const Command.detailed('systemctl', arguments: <String>['daemon-reload'], elevated: true),
    );
  }

  /// What the service file held before, or null when it was not there.
  ///
  /// A machine that arrived with a service of this name gets its file back rather than losing it,
  /// and the service manager is told to read the directory again either way.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    // Stopping it first is what takes the rules out of the kernel — putting the file back or
    // deleting it would leave them there with nothing on the machine saying they exist.
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

  /// What goes in each slot of the service file.
  ///
  /// The rule is described by the same three numbers the step that writes the script composes it
  /// from — the mark, the table and the number — so what the service takes out of the kernel and
  /// what put it there are one description. The program row is where the two are seen to agree.
  Map<String, String> get values => <String, String>{
    'script-path': scriptPath,
    'table-name': tableName,
    'mark': mark,
    'table': '$table',
    'priority': '$priority',
  };
}
