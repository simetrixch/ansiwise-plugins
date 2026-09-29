import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';
import 'remove_default_ipv4_ippool.dart';
import 'reapply_calico_manifest.dart';

/// Waits until the cluster's IPv4 pools cover the new range and no other, and puts the default pool
/// right once where it came back on the old range.
///
/// **The race this answers was measured on a fresh install.** The first look at the pool found
/// nothing, because Calico had not created it yet, so the delete had nothing to delete and was
/// skipped. The agent that was already running then created the pool from its OLD environment,
/// before the restart handed it the new one — and Calico never mutates a pool that exists. The
/// cluster converged on the range the whole conversion exists to leave behind, with every step
/// reporting success.
///
/// **Where the pool for the new range was put in before the default one went, that race cannot
/// happen**: an agent that starts with its old environment finds an IPv4 pool and creates none. There
/// the first look finds the cluster converged and the heal never runs, which makes this step the
/// proof of that order rather than its repair.
///
/// **The heal is one delete and no more.** A default pool that is present and carries the wrong range
/// is deleted a second time and the agent — which now carries the stamped environment — is replaced,
/// so the pool it creates next is the right one. Doing that in a loop would be a machine deleting a
/// pool over and over against something it cannot fix, so it happens once per run and the polling
/// then runs out. A pool on another range under any other name is never deleted: this program did
/// not create it, and the wait runs out naming it.
final class VerifyIppoolConvergedWithSelfHeal extends IrreversibleStep {
  /// Polls for [podCidr] for up to [timeoutSeconds], healing once on a pool that carries another.
  const VerifyIppoolConvergedWithSelfHeal({
    required this.podCidr,
    required this.timeoutSeconds,
    required this.intervalSeconds,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory VerifyIppoolConvergedWithSelfHeal.fromArguments(Arguments arguments) =>
      VerifyIppoolConvergedWithSelfHeal(
        podCidr: arguments.text('pod_cidr'),
        timeoutSeconds: arguments.integer('timeout_seconds'),
        intervalSeconds: arguments.integer('interval_seconds'),
        rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
        kubectl: Kubectl.fromArguments(arguments),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      describes: 'how long the pool is given to come back on the new range',
      required: false,
      defaultValue: 180,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 3600,
        because:
            'a gap of zero seconds asks without pausing, and one longer than an hour is a wait rather than a gap between looks',
      ),
      describes: 'how long to leave between looks at the pool',
      required: false,
      defaultValue: 5,
    ),
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      describes: 'how long the network agent is given to be replaced when the pool is healed',
      required: false,
      defaultValue: 120,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The range every pod gets an address out of.
  final String podCidr;

  /// How long the pool is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// How long a heal's rollout is given.
  final int rolloutTimeoutSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'putting the pool right means deleting it once more, and a pool a running cluster is using is '
      'gone the moment it is deleted — every pod holding an address out of it keeps that address '
      'with nothing routing to it, and nothing wrote down which pods those were';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({Map<String, String>? pools, String? refusal}) reading =
        await RemoveDefaultIpv4Ippool.livePools(context, kubectl);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Map<String, String> pools = reading.pools!;
    if (_converged(pools)) {
      return CheckResult.satisfied('${_described(pools)}, and no IPv4 pool covers another range');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    'would watch the address pools for up to ${timeoutSeconds}s until one covers $podCidr and no '
    'IPv4 pool covers another range and, on a ${RemoveDefaultIpv4Ippool.poolName} that came back '
    'covering another range, delete it once more and replace the network agent',
  );

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    bool healed = false;

    while (true) {
      final ({Map<String, String>? pools, String? refusal}) reading =
          await RemoveDefaultIpv4Ippool.livePools(context, kubectl);
      // WAITING OUT A CLUSTER THAT WOULD NOT ANSWER IS NOT WATCHING A POOL. Read as "there is no
      // pool", a cluster that could not be asked left this loop healing nothing and then reporting
      // that the pool never came back covering the range - a deadline blamed on the pool.
      if (reading.refusal case final String refusal) {
        throw StateError(refusal);
      }
      final Map<String, String> pools = reading.pools!;
      if (_converged(pools)) {
        return;
      }
      final String? back = _elsewhere(pools)[RemoveDefaultIpv4Ippool.poolName];
      if (back != null && !healed) {
        healed = true;
        context.log.warn(
          '${RemoveDefaultIpv4Ippool.poolName} came back covering $back rather than $podCidr — the '
          'agent created it before the restart handed it the new range. Deleting it once more and '
          'replacing the agent, which now carries the stamped range.',
        );
        await RemoveDefaultIpv4Ippool.delete(context, kubectl);
        await _rollNetworkAgent(context);
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(
          waitingFor:
              'a pool to cover $podCidr and none to cover another range — ${_described(pools)}',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  /// Whether an IPv4 pool covers [podCidr] and none covers another range.
  bool _converged(Map<String, String> pools) =>
      pools.values.contains(podCidr) && _elsewhere(pools).isEmpty;

  /// The IPv4 pools on a range other than [podCidr], by name.
  Map<String, String> _elsewhere(Map<String, String> pools) => <String, String>{
    for (final MapEntry<String, String> pool in pools.entries)
      if (pool.value != podCidr && RemoveDefaultIpv4Ippool.isIpv4(pool.value)) pool.key: pool.value,
  };

  /// What the cluster's pools cover, for a verdict and for a deadline that has to name them.
  static String _described(Map<String, String> pools) => pools.isEmpty
      ? 'there is no pool'
      : pools.entries
            .map((MapEntry<String, String> pool) => '${pool.key} covers ${pool.value}')
            .join(', ');

  Future<void> _rollNetworkAgent(StepContext context) async {
    await context.shell.run(
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'restart',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
      ]),
    );
    await context.shell.run(
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'status',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
        '--timeout=${rolloutTimeoutSeconds}s',
      ]),
    );
  }
}
