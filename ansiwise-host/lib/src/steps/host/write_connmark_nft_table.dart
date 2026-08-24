import 'package:ansiwise_core/ansiwise_core.dart';
import 'measure_public_nic.dart';

/// Writes the rules that mark a connection arriving on the public address, so its replies can be
/// steered.
///
/// **This is the half the network configuration cannot do.** The rules written there match on the
/// SOURCE address, which works for traffic the machine itself sends. It does not work for the
/// traffic that matters most: a request to a published port is handed to a pod, and the pod's reply
/// is sourced from the pod's own address rather than from the public one. So a connection that
/// arrived on the public interface is marked when it starts, the mark is put back onto the packets
/// of the reply, and a rule keyed on the mark steers them.
///
/// **The mark is one that nothing else uses.** The network agent, the service proxy and the port
/// publisher each own their own bits and reconcile them; this one is outside all three and outside
/// the agent's own mask, and it lives in a table of its own that none of them ever rewrites.
///
/// **The file begins by removing the table it is about to define.** Loading it a second time then
/// replaces what is there instead of adding to it, which is what makes reloading safe.
final class WriteConnmarkNftTable extends ReversibleStep<String?> with FileStep, TemplateStep {
  /// Writes the rules at [path], marking connections with [mark].
  const WriteConnmarkNftTable({
    required this.templatePath,
    required this.path,
    required this.tableName,
    required this.mark,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory WriteConnmarkNftTable.fromArguments(Arguments arguments) => WriteConnmarkNftTable(
    templatePath: arguments.text('template'),
    path: arguments.text('path'),
    tableName: arguments.text('table_name'),
    mark: arguments.text('mark'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the rule set as text, with a marked slot where each value this run holds belongs — '
          '<device>, <address>, <table-name> and <mark>',
    ),
    // No defaults for the path, the table name or the mark. Which bit is free depends on what else
    // runs on the machine — the network agent, the service proxy and the port publisher each own
    // their own — so the value has to be picked against THAT machine and stands in the program row.
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the rules that mark connections arriving on the public address',
    ),
    ArgumentSpec(
      name: 'table_name',
      kind: ArgumentKind.text,
      describes: 'the nft table the rules live in, which nothing else on the machine defines',
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes: 'the mark put on those connections, which nothing else on the machine uses',
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

  /// `0644` — a rule set that carries nothing secret and that the loader reads.
  static const int fileMode = 0x1a4;

  /// The rule set as text, with a marked slot where each value belongs.

  /// Whether the file belongs to root, so every read and write of it is elevated.
  @override
  final bool elevated;
  @override
  final String templatePath;

  /// The rules' path.
  final String path;

  /// The nft table the rules live in.
  final String tableName;

  /// The mark put on connections arriving on the public address.
  final String mark;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => fileMode;

  /// The rules for the interface this machine's public address arrives on.
  ///
  /// A machine with no such interface steers nothing, so no connection has to be marked — and the
  /// rules could not be composed there in any case, since they name the interface and the address.
  /// One reading answers both, which is why the mixin asks one question.
  @override
  Future<FileContent> contentFor(StepContext context) async {
    final PublicNic? nic = await MeasurePublicNic.measure(context);
    return nic == null
        ? const FileContent.nothing(
            'nothing is steered on this machine, so no connection has to be marked',
          )
        : FileContent.text(await renderedWith(context, valuesFor(nic)));
  }

  /// What the rules file held before, or null when it was not there.
  ///
  /// The undo puts that text back rather than deleting whatever is at the path, so a machine that
  /// arrived with a rule set of this name keeps it — the table in the kernel goes either way.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    await context.shell.run(
      Command.detailed(
        'nft',
        arguments: <String>['destroy', 'table', 'inet', tableName],
        elevated: true,
      ),
    );
    if (captured == null) {
      await context.files.delete(path, elevated: elevated);
      return;
    }
    await context.files.write(path, captured, mode: mode, elevated: elevated);
  }

  /// What goes in each slot of the rule set, for the interface [nic] describes.
  ///
  /// [tableName] is filled in rather than written into the template, because [undo] takes the table
  /// out of the kernel by that same name — one value, so the file and the undo cannot come to name
  /// different tables.
  Map<String, String> valuesFor(PublicNic nic) => <String, String>{
    'device': nic.device,
    'address': nic.address,
    'table-name': tableName,
    'mark': mark,
  };
}
