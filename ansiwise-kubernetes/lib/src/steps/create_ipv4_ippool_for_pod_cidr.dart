import 'dart:convert' show JsonEncoder;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';
import 'reapply_calico_manifest.dart';
import 'remove_default_ipv4_ippool.dart';

/// Puts the address pool for the new range into the cluster BEFORE the default one is deleted, so no
/// start of the network agent meets a cluster without an IPv4 pool.
///
/// **This is what takes the race out of the conversion.** Calico's agent creates its default pool at
/// start only where no IPv4 pool exists — `configureIPPools` in projectcalico/calico
/// `node/pkg/lifecycle/startup/startup.go`, read at v3.29.3. An agent
/// that starts with its old environment while this pool stands finds a pool and creates none, so the
/// delete of the default pool leaves nothing that can come back on the old range.
///
/// **The pool is the one the agent would create, on the new range.** Its settings are read off the
/// agent's set in the cluster, which is the environment the agent creates its default pool from, and
/// each setting the set does not declare takes the value the agent gives it. The range is this
/// row's. The pool is written as the cluster stores it, so the defaults Calico's client adds to a pool
/// it creates are written out here: nothing adds them to an object applied directly.
///
/// **Nothing is created where a pool already covers the range.** On a cluster converted before, the
/// default pool carries it, and a second pool over the same range is one Calico's address management
/// is not built for.
final class CreateIpv4IppoolForPodCidr extends IrreversibleStep {
  /// Creates the pool for [podCidr], written to [poolManifestPath] before it is applied.
  const CreateIpv4IppoolForPodCidr({
    required this.podCidr,
    required this.poolManifestPath,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory CreateIpv4IppoolForPodCidr.fromArguments(Arguments arguments) =>
      CreateIpv4IppoolForPodCidr(
        podCidr: arguments.text('pod_cidr'),
        poolManifestPath: arguments.text('pool_manifest_path'),
        kubectl: Kubectl.fromArguments(arguments),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'pool_manifest_path',
      kind: ArgumentKind.text,
      describes:
          'where the pool is written before it is applied, so what was applied can be looked at '
          '— where that file sits is a fact about the installation',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The name the pool for the new range is created under.
  static const String poolName = 'pod-cidr-ipv4-ippool';

  /// The range every pod gets an address out of.
  final String podCidr;

  /// Where the pool is written before it is applied.
  final String poolManifestPath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'a pool the cluster hands addresses out of cannot be taken away again without stranding every '
      'pod that took one, and nothing wrote down which pods those are';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({Map<String, String>? pools, String? refusal}) reading =
        await RemoveDefaultIpv4Ippool.livePools(context, kubectl);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Map<String, String> pools = reading.pools!;
    for (final MapEntry<String, String> pool in pools.entries) {
      if (pool.value == podCidr) {
        return CheckResult.satisfied('${pool.key} covers $podCidr');
      }
    }
    if (pools[poolName] case final String standing) {
      return CheckResult.blocked(
        '$poolName stands on $standing, and a pool is not moved to another range in place — the '
        'addresses it handed out would stand outside it',
      );
    }
    final ({Map<String, Object>? spec, String? refusal}) pool = await _pool(context);
    if (pool.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(kubectl.argv(<String>['apply', '-f', poolManifestPath]));

  @override
  Future<void> apply(StepContext context) async {
    final ({Map<String, Object>? spec, String? refusal}) pool = await _pool(context);
    if (pool.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final int cut = poolManifestPath.lastIndexOf('/');
    if (cut > 0) {
      await context.files.createDirectory(
        poolManifestPath.substring(0, cut),
        mode: 0x1ed,
        elevated: elevated,
      );
    }
    await context.files.write(
      poolManifestPath,
      const JsonEncoder.withIndent('  ').convert(<String, Object>{
        'apiVersion': 'crd.projectcalico.org/v1',
        'kind': 'IPPool',
        'metadata': <String, Object>{'name': poolName},
        'spec': pool.spec!,
      }),
      mode: 0x1a4,
      elevated: elevated,
    );
    final Command command = kubectl.command(<String>['apply', '-f', poolManifestPath]);
    final CommandResult applied = await context.shell.run(command);
    if (!applied.ok) {
      throw CommandFailed(
        argv: command.argv,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }
  }

  /// The spec of the pool, or why it could not be worked out.
  ///
  /// Each setting is read the way the agent reads it for its default pool, and takes the agent's
  /// value where the set declares none: no IPIP and no VXLAN, blocks of 26, outgoing NAT on, BGP
  /// export on, every node, and the pool used for workloads and tunnels.
  Future<({Map<String, Object>? spec, String? refusal})> _pool(StepContext context) async {
    final Map<String, String> declared = <String, String>{};
    for (final String variable in _variables) {
      final String? value = await ReapplyCalicoManifest.declaredEnv(context, kubectl, variable);
      if (value == null) {
        return (
          spec: null,
          refusal:
              '${ReapplyCalicoManifest.daemonSet} in ${ReapplyCalicoManifest.namespace} could not be '
              'read, and its environment is what the pool takes its settings from',
        );
      }
      declared[variable] = value;
    }
    final String? ipipMode = _mode(declared['CALICO_IPV4POOL_IPIP']!);
    final String? vxlanMode = _mode(declared['CALICO_IPV4POOL_VXLAN']!);
    final String blockSizeText = declared['CALICO_IPV4POOL_BLOCK_SIZE']!;
    final int? blockSize = blockSizeText.isEmpty ? 26 : int.tryParse(blockSizeText);
    final List<String> unreadable = <String>[
      if (ipipMode == null) 'CALICO_IPV4POOL_IPIP',
      if (vxlanMode == null) 'CALICO_IPV4POOL_VXLAN',
      if (blockSize == null || blockSize < 20 || blockSize > 32) 'CALICO_IPV4POOL_BLOCK_SIZE',
    ];
    if (unreadable.isNotEmpty) {
      return (
        spec: null,
        refusal:
            '${ReapplyCalicoManifest.daemonSet} declares ${unreadable.map((String v) => '$v="${declared[v]}"').join(', ')}, '
            'which the agent does not accept either — it would not start with it',
      );
    }
    final String nodeSelector = declared['CALICO_IPV4POOL_NODE_SELECTOR']!;
    return (
      spec: <String, Object>{
        'cidr': podCidr,
        'blockSize': blockSize!,
        'ipipMode': ipipMode!,
        'vxlanMode': vxlanMode!,
        'natOutgoing': _flag(declared['CALICO_IPV4POOL_NAT_OUTGOING']!, orElse: true),
        'disableBGPExport': _flag(declared['CALICO_IPV4POOL_DISABLE_BGP_EXPORT']!, orElse: false),
        'nodeSelector': nodeSelector.isEmpty ? 'all()' : nodeSelector,
        'allowedUses': const <String>['Workload', 'Tunnel'],
      },
      refusal: null,
    );
  }

  /// The environment the agent creates its default IPv4 pool from, besides the range.
  static const List<String> _variables = <String>[
    'CALICO_IPV4POOL_IPIP',
    'CALICO_IPV4POOL_VXLAN',
    'CALICO_IPV4POOL_BLOCK_SIZE',
    'CALICO_IPV4POOL_NAT_OUTGOING',
    'CALICO_IPV4POOL_DISABLE_BGP_EXPORT',
    'CALICO_IPV4POOL_NODE_SELECTOR',
  ];

  /// An encapsulation mode as the agent reads it, or null for one it refuses.
  static String? _mode(String declared) => switch (declared.toLowerCase()) {
    '' || 'off' || 'never' => 'Never',
    'crosssubnet' || 'cross-subnet' => 'CrossSubnet',
    'always' => 'Always',
    _ => null,
  };

  /// A switch as the agent reads it: false for the five words it reads as false, true for anything
  /// else, and [orElse] where the set declares none.
  static bool _flag(String declared, {required bool orElse}) => declared.isEmpty
      ? orElse
      : !const <String>{'false', '0', 'no', 'n', 'f'}.contains(declared.toLowerCase());
}
