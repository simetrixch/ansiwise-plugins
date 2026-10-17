import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'container_workload.dart';
import 'kubectl.dart';

/// Makes one container of one workload request the CPU a program names, and makes the pods that are
/// already running carry the request too.
///
/// **A request is what the scheduler and the kernel hold a container to when the machine is busy.**
/// A container with none gets the minimum CPU share while a heavy job saturates the node, so
/// whatever it serves is starved exactly when the machine is under load. Nothing reports it: the
/// container runs, and answers slowly.
///
/// **The comparison is against the RUNNING pods and never only against the declaration.** Patching
/// the workload changes what the next pod will be started with; where the new pod and the serving
/// one want the same port on the machine the new one never starts, and the old one goes on serving
/// without the request. That is why the pods are replaced here, through [ContainerWorkload]: a run
/// that patched and then timed out leaves a pending pod beside a serving one without the request,
/// and the next run must read that as not done.
///
/// **Replacing a pod interrupts what it serves.** What this step CHANGES can be taken back — the
/// request is set to what it was and the pods replaced a second time — and the interruption itself
/// cannot be. A plan carries ONE command, so wherever the apply would both patch and delete, the dry
/// run names the DELETION and says the patch beside it in the plan's own log.
///
/// **The patch is a strategic merge by container name.** A JSON-patch add needs `requests` to exist,
/// and a workload that declares `resources: {}` has none; a merge creates what is missing and
/// touches no other container.
///
/// **A workload that is not there is a skip and not a failure.** This runs after what installs it; on
/// a machine where that is off there is nothing to patch and nothing wrong.
final class PatchContainerResources extends ReversibleStep<ContainerCpuRequest> {
  /// Makes [container] of [kind] [name] in [namespace] request [cpuRequest] of CPU.
  const PatchContainerResources({
    required this.namespace,
    required this.kind,
    required this.name,
    required this.container,
    required this.cpuRequest,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory PatchContainerResources.fromArguments(Arguments arguments) => PatchContainerResources(
    namespace: arguments.text('namespace'),
    kind: arguments.text('kind'),
    name: arguments.text('name'),
    container: arguments.text('container'),
    cpuRequest: arguments.text('cpu_request'),
    rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the workload runs in',
    ),
    ArgumentSpec(
      name: 'kind',
      kind: ArgumentKind.text,
      describes: 'the kind of workload, as the cluster client names it',
    ),
    ArgumentSpec(name: 'name', kind: ArgumentKind.text, describes: 'the workload'),
    ArgumentSpec(
      name: 'container',
      kind: ArgumentKind.text,
      describes: 'the container inside it, by name',
    ),
    ArgumentSpec(
      name: 'cpu_request',
      kind: ArgumentKind.text,
      describes:
          'the CPU that container requests, written as the cluster writes it: millicores such as '
          '400m, or cores such as 1',
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
      describes: 'how long the replacements are given to come up',
      required: false,
      defaultValue: 90,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The namespace the workload runs in.
  final String namespace;

  /// The kind of workload.
  final String kind;

  /// The workload.
  final String name;

  /// The container inside it.
  final String container;

  /// The CPU that container has to request.
  final String cpuRequest;

  /// How long the replacements are given.
  final int rolloutTimeoutSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// The container this step patches, reached the way every step that patches one reaches it.
  ContainerWorkload get _target => ContainerWorkload(
    namespace: namespace,
    kind: kind,
    name: name,
    container: container,
    rolloutTimeoutSeconds: rolloutTimeoutSeconds,
    kubectl: kubectl,
  );

  /// The request in millicores, null where [cpuRequest] is not a quantity of CPU.
  int? get _wantedMillicores => WorkloadContainer.millicores(cpuRequest);

  @override
  Future<CheckResult> check(StepContext context) async {
    // A request this cannot read must not go green: compared as nothing, it differs from every
    // declaration and the step would patch for ever.
    if (_wantedMillicores == null) {
      return CheckResult.blocked(
        '"$cpuRequest" is not a quantity of CPU — it reads as millicores such as 400m, or cores '
        'such as 1',
      );
    }
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Workload? workloadNow = reading.workload;
    if (workloadNow == null) {
      return CheckResult.satisfied(
        'there is no $kind $name in $namespace, so what installs it is not up and there is nothing '
        'to patch',
      );
    }
    final int at = workloadNow.positionOf(container);
    if (at < 0) {
      return CheckResult.blocked(
        '$kind $name in $namespace has no container called $container — it has '
        '${workloadNow.containerNames.join(', ')}',
      );
    }
    if (_lags(workloadNow.containers[at])) {
      return const CheckResult.ready();
    }

    final List<WorkloadPod>? pods = await _target.pods(context, workloadNow.selector);
    if (pods == null) {
      return CheckResult.blocked(
        'the pods of $kind $name in $namespace could not be read, so what is actually serving '
        'cannot be compared with what the cluster declares',
      );
    }
    final List<WorkloadPod> serving = _serving(pods);
    if (serving.isEmpty) {
      return CheckResult.satisfied(
        'no $name pod is running, so there is none serving without the request',
      );
    }
    if (_lagging(serving).isNotEmpty) {
      return const CheckResult.ready();
    }
    return CheckResult.satisfied(
      'the declaration and every running pod of $name request $cpuRequest of CPU',
    );
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return const StepPlan.nothing('there is no such container to patch');
    }
    final String? patch = _lags(workloadNow.containers[at]) ? _requestPatch(cpuRequest) : null;
    final List<WorkloadPod> pods =
        await _target.pods(context, workloadNow.selector) ?? const <WorkloadPod>[];
    // The pods the apply would delete: the stuck ones unconditionally, and the serving ones that
    // lag the request — which is every serving pod the patch would leave behind.
    final List<String> podsToDelete = <String>[
      for (final WorkloadPod pod in pods)
        if (pod.phase == ContainerWorkload.pending) pod.name,
      for (final WorkloadPod pod in _lagging(_serving(pods))) pod.name,
    ];
    if (podsToDelete.isEmpty) {
      return patch == null
          ? StepPlan.nothing(
              'the declaration and every running pod of $name request $cpuRequest of CPU',
            )
          : StepPlan.argv(kubectl.argv(_target.patchCommand('strategic', patch)));
    }
    // A plan carries one command. Of the two the apply would run, the deletion is the one whose
    // consequence cannot be taken back, so the plan names it and the log beside it says the rest.
    if (patch != null) {
      context.log.info(
        'before the deletion the declaration is patched: '
        '${kubectl.argv(_target.patchCommand('strategic', patch)).join(' ')}',
      );
    }
    context.log.warn(
      'every pod this plan names is deleted, and nothing answers on the ports it holds until its '
      'replacement is up — the requests refused in between are not made again',
    );
    return StepPlan.argv(
      kubectl.argv(<String>[..._target.deleteCommand, ...podsToDelete, '--grace-period=10']),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return;
    }
    if (_lags(workloadNow.containers[at])) {
      await _target.mustRun(context, _target.patchCommand('strategic', _requestPatch(cpuRequest)));
    }
    await _target.replacePods(context, workloadNow.selector, _lagging);
  }

  /// The request the container declared before this ran, so an undo puts back exactly that.
  ///
  /// A reading nobody could take throws instead of capturing none: none is what an undo answers by
  /// removing the request, and a container that carried one before this ran would lose it.
  @override
  Future<ContainerCpuRequest> capture(StepContext context) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      throw StateError(
        'what $kind $name in $namespace requested before this ran could not be read, so an undo '
        'could not put it back: $refusal',
      );
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return const ContainerCpuRequest(null);
    }
    return ContainerCpuRequest(workloadNow.containers[at].cpuRequest);
  }

  @override
  Future<void> undo(StepContext context, ContainerCpuRequest captured) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal != null) {
      return;
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return;
    }
    // A run that asked for what was already there changed nothing, and replacing the pods for it
    // would interrupt what they serve for no reason.
    if (WorkloadContainer.millicores(captured.request) == _wantedMillicores) {
      return;
    }
    // A rejected patch must throw, so it is recorded as not taken back — reported as taken back,
    // the pods that come back still carry the request this run set.
    await _target.mustRun(
      context,
      _target.patchCommand('strategic', _requestPatch(captured.request)),
    );
    // The declaration no longer carries the request and a pod started before this does, which is
    // the same gap the apply closes — read from the other side.
    await _target.replacePods(
      context,
      workloadNow.selector,
      (List<WorkloadPod> serving) => <WorkloadPod>[
        for (final WorkloadPod pod in serving)
          if (pod.container.cpuRequestMillicores == _wantedMillicores) pod,
      ],
    );
  }

  /// Whether [declared] requests anything other than what this program asks for.
  bool _lags(WorkloadContainer declared) => declared.cpuRequestMillicores != _wantedMillicores;

  /// The pods of [pods] that are serving.
  List<WorkloadPod> _serving(List<WorkloadPod> pods) => <WorkloadPod>[
    for (final WorkloadPod pod in pods)
      if (pod.phase == ContainerWorkload.running) pod,
  ];

  /// The pods of [serving] that request anything other than what this program asks for.
  List<WorkloadPod> _lagging(List<WorkloadPod> serving) => <WorkloadPod>[
    for (final WorkloadPod pod in serving)
      if (_lags(pod.container)) pod,
  ];

  /// The merge patch that sets the request of this step's container to [cpu], or removes it where
  /// [cpu] is null — a merge deletes a key it is given as null.
  String _requestPatch(String? cpu) => jsonEncode(<String, Object>{
    'spec': <String, Object>{
      'template': <String, Object>{
        'spec': <String, Object>{
          'containers': <Object>[
            <String, Object?>{
              'name': container,
              'resources': <String, Object>{
                'requests': <String, Object?>{'cpu': cpu},
              },
            },
          ],
        },
      },
    },
  });
}

/// The CPU a container requested before a run set it, so the undo of that run can put it back.
final class ContainerCpuRequest {
  /// Records that the container requested [request], or nothing where that is null.
  const ContainerCpuRequest(this.request);

  /// The request as the cluster wrote it, null where the container requested none.
  final String? request;
}
