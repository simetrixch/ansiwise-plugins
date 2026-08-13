import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';
import 'guard_populated_cluster_pod_cidr_migration.dart';

/// Gives the system pods that came up before the conversion an address out of the new pool.
///
/// **A restart does not give a running pod a new address.** Every pod that was up before the pool
/// was swapped keeps the address it was handed out of the pool that is now gone — a reservation in a
/// block nothing routes to. Recreating the pod is what hands it a new one, and every pod in this
/// namespace is built by a controller, so recreating it is safe.
///
/// **The network agent itself is on the host's own network and must never be touched.** It holds no
/// address out of the pool, so deleting it would take the cluster's networking away for nothing. The
/// one pod that is always here and always affected is the network controller.
///
/// **This comes last, after the pool has converged.** Recreating the pods while the pool is still
/// the old one simply hands them addresses out of the old one again.
final class RecycleKubeSystemPodIps extends IrreversibleStep {
  /// Recreates every pod of the system namespace whose address is outside [podCidr].
  const RecycleKubeSystemPodIps({required this.podCidr, this.kubectl = const Kubectl()});

  /// Builds the step from what the program gave it.
  factory RecycleKubeSystemPodIps.fromArguments(Arguments arguments) => RecycleKubeSystemPodIps(
    podCidr: arguments.text('pod_cidr'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    Kubectl.argument,
  ];

  /// The range every pod gets an address out of.
  final String podCidr;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'the pods are deleted. Their controllers build them again, so the cluster comes back, but the '
      'processes that were running and the addresses they held do not — and whatever they were in '
      'the middle of is gone with them';

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<_Pod>? pods = await _pods(context);
    if (pods == null) {
      return const CheckResult.blocked(
        'the pods of ${GuardPopulatedClusterPodCidrMigration.systemNamespace} could not be read, and '
        'their addresses are what says whether the conversion reached them',
      );
    }
    final List<_Pod> stale = _stale(pods);
    if (stale.isEmpty) {
      return CheckResult.satisfied(
        'every pod of ${GuardPopulatedClusterPodCidrMigration.systemNamespace} on the pod network '
        'holds an address inside $podCidr',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final List<_Pod> stale = _stale(await _pods(context) ?? const <_Pod>[]);
    return StepPlan.argv(
      kubectl.argv(<String>[..._delete, for (final _Pod pod in stale) pod.name, '--wait=false']),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final List<_Pod> stale = _stale(await _pods(context) ?? const <_Pod>[]);
    for (final _Pod pod in stale) {
      context.log.debug(
        '${pod.name} holds ${pod.address}, which is outside $podCidr — recreating it',
      );
      final Command delete = kubectl.command(<String>[..._delete, pod.name, '--wait=false']);
      final CommandResult deleted = await context.shell.run(delete);
      if (!deleted.ok) {
        throw CommandFailed(argv: delete.argv, exitCode: deleted.exitCode, stdout: '',
        stderr: deleted.stderr);
      }
    }
  }

  /// The pods that hold an address the conversion left behind.
  ///
  /// A pod on the host's own network is left out because it holds no address out of the pool, and a
  /// pod with no address yet is left out because there is nothing stale about it.
  List<_Pod> _stale(List<_Pod> pods) => <_Pod>[
    for (final _Pod pod in pods)
      if (!pod.hostNetwork &&
          pod.address.isNotEmpty &&
          !cidrContains(podCidr, pod.address))
        pod,
  ];

  Future<List<_Pod>?> _pods(StepContext context) async {
    final CommandResult pods = await context.shell.run(
      kubectl.observing(<String>[
        '-n',
        GuardPopulatedClusterPodCidrMigration.systemNamespace,
        'get',
        'pods',
        '-o',
        r'jsonpath={range .items[*]}{.metadata.name}{" "}{.spec.hostNetwork}{" "}'
            r'{.status.podIP}{"\n"}{end}',
      ]),
    );
    if (!pods.ok) {
      return null;
    }
    return <_Pod>[
      for (final String line in pods.stdout.split('\n'))
        if (_Pod.read(line) case final _Pod pod) pod,
    ];
  }

  static const List<String> _delete = <String>[
    '-n',
    GuardPopulatedClusterPodCidrMigration.systemNamespace,
    'delete',
    'pod',
  ];
}

/// One pod of the system namespace, as far as this step cares about it.
final class _Pod {
  const _Pod({required this.name, required this.hostNetwork, required this.address});

  /// The pod one line of the reading describes, or null when the line describes none.
  ///
  /// Split on the single separator the reading writes, never on runs of whitespace. The host-network
  /// field is ABSENT rather than false on a pod that is not on one, so its position on the line is
  /// empty — and a split that collapsed the two separators into one would read the address as the
  /// host-network answer and every such pod as being on the host's own network, which is exactly the
  /// pod this step must not skip.
  static _Pod? read(String line) {
    final List<String> fields = line.trimRight().split(' ');
    if (fields.isEmpty || fields.first.trim().isEmpty) {
      return null;
    }
    return _Pod(
      name: fields[0].trim(),
      hostNetwork: fields.length > 1 && fields[1] == 'true',
      address: fields.length > 2 ? fields[2].trim() : '',
    );
  }

  final String name;
  final bool hostNetwork;
  final String address;
}
