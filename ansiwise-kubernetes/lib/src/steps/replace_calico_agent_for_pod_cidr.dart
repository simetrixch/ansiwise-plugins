import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';
import 'reapply_calico_manifest.dart';

/// Replaces the network agent's pods so the running ones carry the new range.
///
/// **The agent reads its range from its own environment, which it only takes again when its pods
/// are replaced.** Applying the stamped manifest declares the range on the set, and every pod that
/// was already running keeps the environment it was started with — so the set is rolled here, after
/// the manifest carries the range and the pool built from the old one is gone.
///
/// **What proves it happened is the running pods, not the rollout.** A rollout that was asked for
/// and never completed reports the same zero as one that did, so after the rollout this reads the
/// range off every pod that is actually running and fails on one that still carries another. The
/// quantifier is EVERY pod on purpose: a proof satisfied by any one pod reports success while a
/// stale pod still runs, which on a set with one pod per machine is exactly the failure to catch.
final class ReplaceCalicoAgentForPodCidr extends IrreversibleStep {
  /// Rolls the network agent and proves the running pods carry [podCidr].
  const ReplaceCalicoAgentForPodCidr({
    required this.podCidr,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory ReplaceCalicoAgentForPodCidr.fromArguments(Arguments arguments) =>
      ReplaceCalicoAgentForPodCidr(
        podCidr: arguments.text('pod_cidr'),
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

  /// How long the rollout is given.
  final int rolloutTimeoutSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      "the network agent's pods have been replaced and now run against the new range, and rolling "
      'the set again is another replacement rather than the inverse of the first';

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String>? running = await _runningRanges(context);
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
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(
    kubectl.argv(<String>[
      '-n',
      ReapplyCalicoManifest.namespace,
      'rollout',
      'restart',
      'daemonset/${ReapplyCalicoManifest.daemonSet}',
    ]),
  );

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>[
      '-n',
      ReapplyCalicoManifest.namespace,
      'rollout',
      'restart',
      'daemonset/${ReapplyCalicoManifest.daemonSet}',
    ]);
    await _mustRun(context, <String>[
      '-n',
      ReapplyCalicoManifest.namespace,
      'rollout',
      'status',
      'daemonset/${ReapplyCalicoManifest.daemonSet}',
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);

    // The proof the rollout's own zero cannot give. A pod that could not be read proves nothing,
    // and nothing proven is a failure here rather than a pass: the steps behind this one build the
    // pool on the assumption that every agent pod already carries the range.
    final List<String>? running = await _runningRanges(context);
    if (running == null || running.isEmpty) {
      throw StateError(
        'the ${ReapplyCalicoManifest.daemonSet} pods could not be read back after the rollout, so '
        'nothing proves the running agent carries $podCidr',
      );
    }
    final List<String> stale = <String>[
      for (final String cidr in running)
        if (cidr != podCidr) cidr,
    ];
    if (stale.isNotEmpty) {
      throw StateError(
        'the rollout reported success and a running ${ReapplyCalicoManifest.daemonSet} pod still '
        'carries ${stale.join(', ')} rather than $podCidr — the agent was not replaced everywhere',
      );
    }
  }

  /// The range each running agent pod carries, or null when the pods cannot be read.
  Future<List<String>?> _runningRanges(StepContext context) async {
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
            '[?(@.name=="${ReapplyCalicoManifest.variable}")].value}'
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

  Future<void> _mustRun(StepContext context, List<String> arguments) async {
    final Command command = kubectl.command(arguments);
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
