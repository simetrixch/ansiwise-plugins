import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';
import 'delete_default_ipv4_ippool.dart';
import 'reapply_calico_manifest.dart';

/// Waits for the address pool to come back on the new range, and puts it right once when it does not.
///
/// **The race this answers was measured on a fresh install.** The first look at the pool found
/// nothing, because Calico had not created it yet, so the delete had nothing to delete and was
/// skipped. The agent that was already running then created the pool from its OLD environment,
/// before the restart handed it the new one — and Calico never mutates a pool that exists. The
/// cluster converged on the range the whole conversion exists to leave behind, with every step
/// reporting success.
///
/// **The heal is one delete and no more.** A pool that is present and carries the wrong range is
/// deleted a second time and the agent — which now carries the stamped environment — is replaced, so
/// the pool it creates next is the right one. Doing that in a loop would be a machine deleting a
/// pool over and over against something it cannot fix, so it happens once per run and the polling
/// then runs out.
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
      describes: 'how long the pool is given to come back on the new range',
      required: false,
      defaultValue: 180,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks at the pool',
      required: false,
      defaultValue: 5,
    ),
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
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
    final String? live = await DeleteDefaultIpv4Ippool.liveCidr(context, kubectl);
    if (live == podCidr) {
      return CheckResult.satisfied('${DeleteDefaultIpv4Ippool.poolName} covers $podCidr');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    'would watch ${DeleteDefaultIpv4Ippool.poolName} for up to ${timeoutSeconds}s and, on a pool '
    'that came back covering another range, delete it once more and replace the network agent',
  );

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    bool healed = false;

    while (true) {
      final String? live = await DeleteDefaultIpv4Ippool.liveCidr(context, kubectl);
      if (live == podCidr) {
        return;
      }
      if (live != null && !healed) {
        healed = true;
        context.log.warn(
          '${DeleteDefaultIpv4Ippool.poolName} came back covering $live rather than $podCidr — the '
          'agent created it before the restart handed it the new range. Deleting it once more and '
          'replacing the agent, which now carries the stamped range.',
        );
        await DeleteDefaultIpv4Ippool.delete(context, kubectl);
        await _rollNetworkAgent(context);
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(
          waitingFor:
              '${DeleteDefaultIpv4Ippool.poolName} to cover $podCidr — it '
              '${live == null ? 'does not exist' : 'covers $live'}',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

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
