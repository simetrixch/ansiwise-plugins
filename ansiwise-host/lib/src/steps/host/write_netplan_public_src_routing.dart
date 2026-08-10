import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

/// Writes the network drop-in that sends replies from the public address out the public gateway.
///
/// **The drop-in has to FOLD INTO the installer's own declaration of the interface, not sit beside
/// it.** The network configuration is merged from every file in the directory, and two files that
/// describe the same interface differently are two declarations rather than one — the interface then
/// loses the address configuration the installer gave it. So this is keyed exactly the way the
/// installer's file is keyed: on the interface's hardware address and the name it is given. The step
/// after this one proves the fold happened before anything is applied.
///
/// **The file is readable by its owner and nobody else.** The network tool refuses to read a file
/// anyone can read, and says so loudly rather than quietly ignoring it — which would leave a machine
/// whose drop-in is present, correct and doing nothing.
///
/// **The four exceptions come before the catch-all, and the numbers are what decide it.** A lower
/// number wins in the kernel, so the routes that must stay on the main table are numbered below the
/// one that sends everything else out the public gateway. The carrier-grade range is among them
/// because a certificate service checks its own answer over exactly that path, and steering that
/// check out the public gateway makes every certificate on the cluster fail to be issued. Which
/// ranges those are, which numbers they carry and which table they stay on are the template's own
/// text: they are facts of the kernel and of the product the template belongs to, the same on
/// every machine, so nothing about a run has a value to put there.
final class WriteNetplanPublicSrcRouting extends ReversibleStep<String?>
    with FileStep, TemplateStep {
  /// Writes the drop-in at [path], sending everything else through table [table].
  const WriteNetplanPublicSrcRouting({
    required this.templatePath,
    required this.path,
    required this.table,
  });

  /// Builds the step from what the program gave it.
  factory WriteNetplanPublicSrcRouting.fromArguments(Arguments arguments) =>
      WriteNetplanPublicSrcRouting(
        templatePath: arguments.text('template'),
        path: arguments.text('path'),
        table: arguments.integer('table'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'template',
      kind: ArgumentKind.text,
      describes:
          'the drop-in as text, with a marked slot where each value this run holds belongs — '
          '<device>, <address>, <mac>, <gateway> and <table>',
    ),
    // No defaults for the drop-in's name or the table number. The file name decides the ORDER the
    // network tool merges the directory in, and the table number has to be free of whatever else
    // the machine already routes with — both are the installation's to pick, so the program row
    // states them.
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the drop-in that steers replies from the public address — its name decides where it '
          'falls in the merge order of the directory it goes in',
    ),
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes:
          'the routing table whose only route is the public gateway, free of every table this '
          'machine already routes with',
    ),
  ];

  /// `0600` — the network tool refuses to read a file anyone can read.
  static const int fileMode = 0x180;

  /// The drop-in as text, with a marked slot where each value belongs.
  @override
  final String templatePath;

  /// The drop-in's path.
  final String path;

  /// The table holding the public gateway.
  final int table;

  @override
  String pathFor(StepContext context) => path;

  @override
  int get mode => fileMode;

  /// The drop-in for the interface this machine's public address arrives on.
  ///
  /// A machine that answers by the same interface its public address is on steers nothing, and the
  /// drop-in could not be composed there in any case, since it names that interface. One reading
  /// answers both.
  @override
  Future<FileContent> contentFor(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    return nic == null
        ? const FileContent.nothing(
            'this machine answers by the interface its public address is on, so nothing has to be '
            'steered',
          )
        : FileContent.text(await renderedWith(context, valuesFor(nic)));
  }

  /// What the drop-in held before, or null when it was not there.
  ///
  /// A drop-in of this name that a previous run wrote goes back as it was, with the permission bits
  /// the network tool insists on — a machine left with no drop-in would answer by whichever
  /// interface holds the default route.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    // Neither writing nor deleting takes the rules out of the kernel. Only applying the
    // configuration again or a restart does, and the step that applies it says what that costs.
    if (captured == null) {
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }

  /// What goes in each slot of the drop-in, for the interface [nic] describes.
  Map<String, String> valuesFor(PublicNic nic) => <String, String>{
    'device': nic.device,
    'address': nic.address,
    'mac': nic.mac,
    'gateway': nic.gateway,
    'table': '$table',
  };
}
