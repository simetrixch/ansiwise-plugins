import 'package:ansiwise_core/ansiwise_core.dart';
import 'delete_default_ipv4_ippool.dart';
import 'kubectl.dart';

/// Refuses to move the pod network of a cluster that is carrying workloads.
///
/// **What the refusal is protecting against.** The conversion deletes the address pool and gives
/// back only the pods of `kube-system`, because those are the ones a controller rebuilds by itself.
/// Every other pod keeps an address out of a pool that no longer exists, with no translation behind
/// it, and stays that way until something recreates it. On a cluster with applications on it that is
/// every one of them.
///
/// **Why a live cluster ever reaches this code.** A routine re-run of the same install program on a
/// machine that is serving traffic runs exactly this phase. The supported path for such a machine
/// is a fresh provision, not a swap underneath the workloads.
///
/// The override exists for a maintenance window, and taking it means restarting every pod on the
/// cluster afterwards — the ones outside `kube-system` included, which nothing here does.
///
/// **A cluster that is already converted is not guarded, because there is nothing to guard.** When
/// the live pool and kube-proxy's arguments both carry the range, no migration is going to happen
/// and the count of workloads does not matter.
final class GuardPopulatedClusterPodCidrMigration extends ObservingStep {
  /// Refuses a populated cluster unless [allowPopulatedMigration] was set.
  const GuardPopulatedClusterPodCidrMigration({
    required this.podCidr,
    required this.argsPath,
    required this.allowPopulatedMigration,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory GuardPopulatedClusterPodCidrMigration.fromArguments(Arguments arguments) =>
      GuardPopulatedClusterPodCidrMigration(
        podCidr: arguments.text('pod_cidr'),
        argsPath: arguments.text('args_path'),
        allowPopulatedMigration: arguments.flag('allow_populated_migration'),
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
      name: 'args_path',
      kind: ArgumentKind.text,
      describes:
          'the file holding the arguments kube-proxy is started with — where that file sits is a '
          'fact about the installation',
    ),
    ArgumentSpec(
      name: 'allow_populated_migration',
      kind: ArgumentKind.flag,
      describes:
          'whether the pod network may be moved on a cluster that is carrying workloads, '
          'which leaves every one of those workloads to be restarted by hand afterwards',
      required: false,
      defaultValue: false,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    // ASKED, never assumed. Whether the file this row points at belongs to root is a property of
    // that PATH, and this step is pointed at one by its row — an arguments file of a system service
    // usually does, a file under a checkout usually does not. Reading and writing as root does not
    // make either act anything other than a read and a write, so a dry run still refuses the write
    // and still performs the read.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the file belongs to root, so that reading and writing it need elevation. Leave '
          'it off for a path this account owns',
      required: false,
    ),
  ];

  /// The namespace whose pods the conversion gives back by itself.
  static const String systemNamespace = 'kube-system';

  /// The flag in kube-proxy's arguments that names the range the pods are on.
  ///
  /// A program row writes it into the file and this reads it back, so the two name the same flag.
  /// kube-proxy decides what counts as leaving the pod network from this one line, and a cluster
  /// whose file still carries the old range is a cluster the conversion has not finished on.
  static const String clusterCidrFlag = '--cluster-cidr';

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The file holding kube-proxy's arguments.
  final String argsPath;

  /// Whether the operator asked for the swap on a populated cluster.
  final bool allowPopulatedMigration;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file belongs to root, so every read and write of it is elevated.
  final bool elevated;
  @override
  bool get restsOnAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await _converged(context)) {
      return CheckResult.satisfied(
        'the pod network already runs on $podCidr and kube-proxy carries it, so no pool is going to '
        'be swapped',
      );
    }

    final List<String>? populated = await _podsOutsideSystem(context);
    if (populated == null) {
      return const CheckResult.blocked(
        'the pods on this cluster could not be counted, and this is what decides whether swapping '
        'the address pool would strand them',
      );
    }
    if (populated.isEmpty) {
      return const CheckResult.satisfied(
        'no pod outside $systemNamespace is on the pod network, so nothing is stranded by the swap',
      );
    }
    if (allowPopulatedMigration) {
      context.log.warn(
        '${populated.length} pod(s) outside $systemNamespace are on the pod network and the swap was '
        'allowed anyway — every one of them keeps an address out of the deleted pool until it is '
        'restarted by hand: ${populated.join(', ')}',
      );
      return CheckResult.satisfied(
        'the swap was allowed on a populated cluster, and ${populated.length} pod(s) have to be '
        'restarted afterwards',
      );
    }
    return CheckResult.blocked(
      '${populated.length} pod(s) outside $systemNamespace are on the pod network — swapping the '
      'address pool leaves every one of them on an address out of a pool that no longer exists, and '
      'only $systemNamespace is given back. The supported path for a machine carrying workloads is a '
      'fresh provision. Set allow_populated_migration when this is a maintenance window and every '
      'pod is restarted afterwards: ${populated.join(', ')}',
    );
  }

  /// Whether both halves of the conversion are already done.
  Future<bool> _converged(StepContext context) async {
    if (await DeleteDefaultIpv4Ippool.liveCidr(context, kubectl) != podCidr) {
      return false;
    }
    if (!await context.files.exists(argsPath, elevated: elevated)) {
      return false;
    }
    final String args = await context.files.read(argsPath, elevated: elevated);
    return _carries(args, '$clusterCidrFlag=$podCidr');
  }

  /// Whether [args] carries [line] exactly, as its own line.
  ///
  /// The convergence question of this phase is asked partly of a file and partly of the cluster.
  /// This is the file half, compared line for line the way the step that writes the flag writes it.
  static bool _carries(String args, String line) =>
      args.split('\n').any((String each) => each.trim() == line);

  /// The pods outside [systemNamespace] that are on the pod network, or null when they cannot be read.
  ///
  /// A pod on the host's own network holds no address out of the pool and is unaffected by the swap,
  /// so it is not counted. The field is absent rather than false on such a pod, which is why the
  /// answer is read as text and only the word `true` counts.
  Future<List<String>?> _podsOutsideSystem(StepContext context) async {
    final CommandResult pods = await context.shell.run(
      kubectl.observing(<String>[
        'get',
        'pods',
        '--all-namespaces',
        '-o',
        r'jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}'
            r'{.spec.hostNetwork}{"\n"}{end}',
      ]),
    );
    if (!pods.ok) {
      return null;
    }
    final List<String> onThePodNetwork = <String>[];
    for (final String line in pods.stdout.split('\n')) {
      // Split on the single separator the reading writes. The host-network field is absent rather
      // than false on a pod that is not on one, so its position is empty and the line then carries
      // two fields instead of three.
      final List<String> fields = line.trimRight().split(' ');
      if (fields.length < 2 || fields[0].trim().isEmpty) {
        continue;
      }
      if (fields[0].trim() == systemNamespace) {
        continue;
      }
      final bool hostNetwork = fields.length > 2 && fields[2].trim() == 'true';
      if (!hostNetwork) {
        onThePodNetwork.add('${fields[0].trim()}/${fields[1].trim()}');
      }
    }
    return onThePodNetwork;
  }
}
