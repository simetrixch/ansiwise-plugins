import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

/// Writes the script that loads the marking rules and installs the rule keyed on the mark.
///
/// **The rule has to be MASKED, and that is the reason this script exists at all.** The network
/// configuration cannot express a masked match, and an unmasked one never fires: the reply packet
/// carries the network agent's own mark as well, so the two marks together are not the one value an
/// unmasked rule is looking for. The rule reads correctly, matches nothing, and the steering
/// silently does not happen.
///
/// **The script removes any rule already at its own number before adding one, and does it in a
/// loop.** Adding without removing leaves a second identical rule on every run, and a single removal
/// leaves whatever a previous run added twice.
final class WritePublicSrcRoutingScript extends ReversibleStep<String?>
    with FileStep, TemplateStep {
  /// Writes the script at [path], installing the rule at [priority].
  const WritePublicSrcRoutingScript({
    required this.templatePath,
    required this.path,
    required this.rulesPath,
    required this.mark,
    required this.table,
    required this.priority,
  });

  /// Builds the step from what the program gave it.
  factory WritePublicSrcRoutingScript.fromArguments(Arguments arguments) =>
      WritePublicSrcRoutingScript(
        templatePath: arguments.text('template'),
        path: arguments.text('path'),
        rulesPath: arguments.text('rules_path'),
        mark: arguments.text('mark'),
        table: arguments.integer('table'),
        priority: arguments.integer('priority'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the script as text, with a marked slot where each value this run holds belongs — '
          '<rules-path>, <mark>, <table> and <priority>',
    ),
    // Nothing here has a default. Every one of the five is a value the installation picked and
    // three of them are picked TWICE — the mark and the table by the two steps that write them,
    // the rules path by the step that writes that file — so a default here would let one row keep
    // a value while another row moved, and the script would then load a file nobody writes or
    // steer into a table nobody fills. The program row states all five, which is the only place
    // the pairs can be seen to agree.
    ArgumentSpec(name: 'path', kind: ArgumentKind.text, describes: 'the script the unit runs'),
    ArgumentSpec(
      name: 'rules_path',
      kind: ArgumentKind.text,
      describes: 'the marking rules the script loads',
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes: 'the mark the rule is keyed on, as the step that writes the rules puts it on',
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
      describes: 'the number the rule keyed on the mark is installed at',
    ),
  ];

  /// `0755` — a script the unit runs.
  static const int fileMode = 0x1ed;

  /// The script as text, with a marked slot where each value belongs.
  @override
  final String templatePath;

  /// The script's path.
  final String path;

  /// The marking rules it loads.
  final String rulesPath;

  /// The mark the rule is keyed on.
  final String mark;

  /// The table the marked replies go into.
  final int table;

  /// The number the rule sits at.
  final int priority;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => fileMode;

  /// The script, on a machine that steers anything at all.
  ///
  /// The text itself names no interface — the script reads that at run time — but a machine with no
  /// public interface of its own has no rule to install and no reason to carry the script that
  /// installs it.
  @override
  Future<FileContent> contentFor(StepContext context) async =>
      await DetectPublicNic.detect(context) == null
      ? const FileContent.nothing(
          'nothing is steered on this machine, so there is no rule to install',
        )
      : FileContent.text(await renderedWith(context, values));

  /// What the script file held before, or null when it was not there.
  ///
  /// The rule keyed on the mark comes out of the kernel either way; what goes back on disk is the
  /// script a previous run wrote, so the service that runs it is not left pointing at nothing.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    await context.shell.run(Command('ip', ruleArguments('del')));
    if (captured == null) {
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }

  /// The arguments that [verb] the rule keyed on the mark.
  List<String> ruleArguments(String verb) => <String>[
    '-4',
    'rule',
    verb,
    'from',
    'all',
    'fwmark',
    '$mark/$mark',
    'lookup',
    '$table',
    'priority',
    '$priority',
  ];

  /// What goes in each slot of the script.
  ///
  /// The four values are the same ones [ruleArguments] composes the undo from, so the rule the
  /// script installs and the rule the undo removes are one description with one set of numbers.
  Map<String, String> get values => <String, String>{
    'rules-path': rulesPath,
    'mark': mark,
    'table': '$table',
    'priority': '$priority',
  };
}
