import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';
import 'reapply_calico_manifest.dart';
import 'stamp_calico_pool_cidr_in_cni_manifest.dart';
import 'wait_for_microk8s_ready.dart';

/// Restarts everything that has to read the new range before the pool can be built on it.
///
/// **Two different things need restarting and neither restarts the other.** kube-proxy has no
/// service of its own — it runs inside kubelite, which comes back with the whole snap — and the
/// network agent reads its range from its own environment, which it only takes again when its pods
/// are replaced. A restart of one leaves the other where it was, which is why this does both and in
/// that order: the snap first, so the agent that comes back is already running against a restarted
/// kubelite.
///
/// **What proves it happened is the running pods, not the restart.** A rollout that was asked for
/// and never completed reports the same zero as one that did, so this reads the range off the pods
/// that are actually running.
final class RestartMicrok8sSnapForPodCidr extends ReversibleStep {
  /// Restarts the snap and rolls the network agent, then proves the pods carry [podCidr].
  const RestartMicrok8sSnapForPodCidr({
    required this.podCidr,
    required this.readyTimeoutSeconds,
    required this.rolloutTimeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory RestartMicrok8sSnapForPodCidr.fromArguments(Arguments arguments) =>
      RestartMicrok8sSnapForPodCidr(
        podCidr: arguments.text('pod_cidr'),
        readyTimeoutSeconds: arguments.integer('ready_timeout_seconds'),
        rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'ready_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the node is given to come back after the restart',
      required: false,
      defaultValue: 300,
    ),
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the network agent is given to be replaced everywhere',
      required: false,
      defaultValue: 120,
    ),
  ];

  /// The range every pod gets an address out of.
  final String podCidr;

  /// How long the node is given to come back.
  final int readyTimeoutSeconds;

  /// How long the rollout is given.
  final int rolloutTimeoutSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String>? running = await runningPoolCidrs(context);
    if (running == null || running.isEmpty) {
      return const CheckResult.ready();
    }
    if (running.every((String cidr) => cidr == podCidr)) {
      return CheckResult.satisfied(
        'every running ${ReapplyCalicoManifest.daemonSet} pod carries $podCidr',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.argv(<String>['snap', 'restart', InstallMicrok8sSnap.snapName]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>['snap', 'restart', InstallMicrok8sSnap.snapName]);

    final CommandResult ready = await context.shell.run(
      Command.detailed(
        'microk8s',
        arguments: <String>['status', '--wait-ready', '--timeout', '$readyTimeoutSeconds'],
        observes: true,
        timeout: Duration(seconds: readyTimeoutSeconds + 30),
      ),
    );
    if (!ready.ok || !ready.stdout.contains(WaitForMicrok8sReady.runningLine)) {
      throw CommandFailed(
        argv: <String>['microk8s', 'status', '--wait-ready'],
        exitCode: ready.exitCode,
        stderr: 'the node did not come back within ${readyTimeoutSeconds}s',
      );
    }

    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      ReapplyCalicoManifest.namespace,
      'rollout',
      'restart',
      'daemonset/${ReapplyCalicoManifest.daemonSet}',
    ]);
    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      ReapplyCalicoManifest.namespace,
      'rollout',
      'status',
      'daemonset/${ReapplyCalicoManifest.daemonSet}',
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  @override
  Future<void> undo(StepContext context) async {
    // A restart leaves no state of its own to take back. What it changed is which processes are
    // running, and by the time an undo could be called they are running again; restarting them a
    // second time would be another restart rather than the inverse of the first.
  }

  /// The range each running network-agent pod carries, or null when the pods cannot be read.
  static Future<List<String>?> runningPoolCidrs(StepContext context) async {
    final CommandResult pods = await context.shell.run(
      const Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        ReapplyCalicoManifest.namespace,
        'get',
        'pods',
        '-l',
        'k8s-app=${ReapplyCalicoManifest.daemonSet}',
        '-o',
        r'jsonpath={range .items[*]}{.spec.containers[0].env'
            '[?(@.name=="${StampCalicoPoolCidrInCniManifest.variable}")].value}'
            r'{"\n"}{end}',
      ]),
    );
    if (!pods.ok) {
      return null;
    }
    return <String>[
      for (final String line in pods.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
