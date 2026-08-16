import 'package:ansiwise_api/ansiwise_api.dart';
// The variable the network agent carries its range in is Calico's own name for it, and the step
// that stamps it into the manifest on disk is a machine capability now. Read from there rather than
// spelled again here, so the stamp and this proof cannot come to mean two different variables.
import 'stamp_calico_pool_cidr_in_cni_manifest.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'microk8s.dart';

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
final class RestartMicrok8sSnapForPodCidr extends IrreversibleStep {
  /// Restarts the snap and rolls the network agent, then proves the pods carry [podCidr].
  const RestartMicrok8sSnapForPodCidr({
    required this.podCidr,
    required this.readyTimeoutSeconds,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory RestartMicrok8sSnapForPodCidr.fromArguments(Arguments arguments) =>
      RestartMicrok8sSnapForPodCidr(
        podCidr: arguments.text('pod_cidr'),
        readyTimeoutSeconds: arguments.integer('ready_timeout_seconds'),
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
    Kubectl.argument,
  ];

  /// The range every pod gets an address out of.
  final String podCidr;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// How long the node is given to come back.
  final int readyTimeoutSeconds;

  /// How long the rollout is given.
  final int rolloutTimeoutSeconds;

  /// The room the readiness command has beyond the budget it was given.
  ///
  /// Named rather than written into the call, because the number is not arbitrary and the obvious
  /// tidy-up is to remove it: it is what makes the outer kill lose the race.
  static const Duration _outerGrace = Duration(seconds: 30);

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String>? running = await runningPoolCidrs(context, kubectl);
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
      const StepPlan.argv(<String>['snap', 'restart', microk8sSnap]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, const Command('snap', <String>['restart', microk8sSnap]));

    // TWO DEADLINES RACE HERE AND THE OUTER ONE HAS TO LOSE. The command is given the budget and
    // reports on its own when the node does not come back; the timeout beside it is only the
    // backstop for a command that never returns at all. The grace is what makes the command's own
    // answer arrive first — without it both expire together and what the operator reads is a bare
    // kill instead of the status line saying which part is not up.
    final CommandResult ready = await context.shell.run(
      Command.detailed(
        'microk8s',
        arguments: <String>['status', '--wait-ready', '--timeout', '$readyTimeoutSeconds'],
        observes: true,
        timeout: Duration(seconds: readyTimeoutSeconds) + _outerGrace,
      ),
    );
    if (!ready.ok || !ready.stdout.contains(microk8sRunningLine)) {
      throw CommandFailed(
        argv: <String>['microk8s', 'status', '--wait-ready'],
        exitCode: ready.exitCode,
        stdout: '',
        stderr: 'the node did not come back within ${readyTimeoutSeconds}s',
      );
    }

    await _mustRun(
      context,
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'restart',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
      ]),
    );
    await _mustRun(
      context,
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

  @override
  String get irreversibleReason =>
      'the cluster\'s network processes have already been restarted against the new range, and a '
      'second restart is another restart rather than the inverse of the first';

  /// The range each running network-agent pod carries, or null when the pods cannot be read.
  static Future<List<String>?> runningPoolCidrs(StepContext context, Kubectl kubectl) async {
    final CommandResult pods = await context.shell.run(
      kubectl.observing(<String>[
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

  Future<void> _mustRun(StepContext context, Command command) async {
    final CommandResult answer = await context.shell.run(command);
    if (!answer.ok) {
      throw CommandFailed(
        argv: command.argv,
        exitCode: answer.exitCode,
        stdout: '',
        stderr: answer.stderr,
      );
    }
  }
}
