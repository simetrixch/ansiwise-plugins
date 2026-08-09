import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

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
final class WriteConnmarkNftTable extends ReversibleStep<String?> {
  /// Writes the rules at [path], marking connections with [mark].
  const WriteConnmarkNftTable({required this.path, required this.mark});

  /// Builds the step from what the program gave it.
  factory WriteConnmarkNftTable.fromArguments(Arguments arguments) =>
      WriteConnmarkNftTable(path: arguments.text('path'), mark: arguments.text('mark'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the rules that mark connections arriving on the public address',
      required: false,
      defaultValue: defaultPath,
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes: 'the mark put on those connections, which nothing else on the machine uses',
      required: false,
      defaultValue: defaultMark,
    ),
  ];

  /// Where the rules go.
  static const String defaultPath = '/etc/nftables.d/hostyour-public-src.nft';

  /// The table these rules live in.
  static const String tableName = 'hostyour-public-src';

  /// The mark, chosen clear of everything else on the machine.
  static const String defaultMark = '0x1000';

  /// `0644` — a rule set that carries nothing secret and that the loader reads.
  static const int mode = 0x1a4;

  /// The rules' path.
  final String path;

  /// The mark put on connections arriving on the public address.
  final String mark;

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    if (nic == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so no connection has to be marked',
      );
    }
    if (!await context.files.exists(path)) {
      return const CheckResult.ready();
    }
    return await context.files.read(path) == ruleset(nic, mark)
        ? CheckResult.satisfied('$path already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    return StepPlan.diff(
      path,
      before: await context.files.exists(path) ? await context.files.read(path) : '',
      after: nic == null ? '' : ruleset(nic, mark),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    if (nic == null) {
      return;
    }
    await context.files.write(path, ruleset(nic, mark), mode: mode);
  }

  /// What the rules file held before, or null when it was not there.
  ///
  /// The undo puts that text back rather than deleting whatever is at the path, so a machine that
  /// arrived with a rule set of this name keeps it — the table in the kernel goes either way.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(path) ? context.files.read(path) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    await context.shell.run(const Command('nft', <String>['destroy', 'table', 'inet', tableName]));
    if (captured == null) {
      await context.files.delete(path);
      return;
    }
    await context.files.write(path, captured, mode: mode);
  }

  /// The rules for [nic], marking its connections with [mark].
  static String ruleset(PublicNic nic, String mark) =>
      '# Connections that arrived on ${nic.device} for ${nic.address} are marked, and the mark is put\n'
      '# back onto the packets of the reply so the rule keyed on it can steer them out the public\n'
      '# gateway. This covers the replies the source-address rules cannot: a reply handed back by a\n'
      '# pod is sourced from the pod, not from ${nic.address}.\n'
      '#\n'
      '# The first line removes the table, so loading this again replaces it rather than adding to\n'
      '# what is already there.\n'
      'destroy table inet $tableName\n'
      '\n'
      'table inet $tableName {\n'
      '  chain prerouting {\n'
      '    type filter hook prerouting priority -150; policy accept;\n'
      '    iifname "${nic.device}" ip daddr ${nic.address} ct state new ct mark set $mark\n'
      '    ct mark $mark meta mark set ct mark\n'
      '  }\n'
      '\n'
      '  chain output {\n'
      '    type route hook output priority -150; policy accept;\n'
      '    ct mark $mark meta mark set ct mark\n'
      '  }\n'
      '}\n';
}
