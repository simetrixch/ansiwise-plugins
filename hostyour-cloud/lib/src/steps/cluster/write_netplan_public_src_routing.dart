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
/// because the certificate service checks its own answer over exactly that path, and steering that
/// check out the public gateway makes every certificate on the cluster fail to be issued.
final class WriteNetplanPublicSrcRouting extends ReversibleStep<String?> with FileStep {
  /// Writes the drop-in at [path], sending everything else through table [table].
  const WriteNetplanPublicSrcRouting({required this.path, required this.table});

  /// Builds the step from what the program gave it.
  factory WriteNetplanPublicSrcRouting.fromArguments(Arguments arguments) =>
      WriteNetplanPublicSrcRouting(path: arguments.text('path'), table: arguments.integer('table'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the drop-in that steers replies from the public address',
      required: false,
      defaultValue: defaultPath,
    ),
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes: 'the routing table whose only route is the public gateway',
      required: false,
      defaultValue: publicTable,
    ),
  ];

  /// Where the drop-in goes.
  static const String defaultPath = '/etc/netplan/60-public-src-routing.yaml';

  /// The table holding the public gateway, and nothing else.
  static const int publicTable = 100;

  /// The kernel's own main table, which the four exceptions stay on.
  static const int mainTable = 254;

  /// `0600` — the network tool refuses to read a file anyone can read.
  static const int fileMode = 0x180;

  /// The ranges that stay on the main table, and the number each is given.
  ///
  /// Every number here is below [catchAllPriority], which is what makes them exceptions to it.
  static const Map<int, String> exceptions = <int, String>{
    9000: '10.0.0.0/8',
    9001: '100.64.0.0/10',
    9002: '172.16.0.0/12',
    9003: '192.168.0.0/16',
  };

  /// The number given to the rule that sends everything else out the public gateway.
  static const int catchAllPriority = 10000;

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
        : FileContent.text(dropIn(nic, table));
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

  /// The drop-in for [nic], sending everything else through [table].
  static String dropIn(PublicNic nic, int table) {
    final StringBuffer written = StringBuffer()
      ..writeln('# Replies to traffic that arrived on ${nic.device} (${nic.address}) leave by')
      ..writeln('# ${nic.gateway} rather than by the default route of another interface.')
      ..writeln('#')
      ..writeln('# Keyed on the same hardware address and name as the installer\'s own file, so')
      ..writeln(
        '# this folds into the one declaration of ${nic.device} instead of becoming a second.',
      )
      ..writeln('network:')
      ..writeln('  version: 2')
      ..writeln('  ethernets:')
      ..writeln('    ${nic.device}:')
      ..writeln('      match:')
      ..writeln('        macaddress: "${nic.mac}"')
      ..writeln('      set-name: ${nic.device}')
      ..writeln('      routing-policy:');
    for (final MapEntry<int, String> exception in exceptions.entries) {
      written
        ..writeln('        - from: ${nic.address}/32')
        ..writeln('          to: ${exception.value}')
        ..writeln('          table: $mainTable')
        ..writeln('          priority: ${exception.key}');
    }
    written
      ..writeln('        - from: ${nic.address}/32')
      ..writeln('          table: $table')
      ..writeln('          priority: $catchAllPriority')
      ..writeln('      routes:')
      ..writeln('        - to: 0.0.0.0/0')
      ..writeln('          via: ${nic.gateway}')
      ..writeln('          on-link: true')
      ..writeln('          table: $table');
    return written.toString();
  }
}
