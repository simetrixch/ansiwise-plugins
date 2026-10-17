import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'container_workload.dart';
import 'kubectl.dart';

/// Makes one container of one workload carry the arguments and publish the ports a program names,
/// and makes the pods that are already running carry them too.
///
/// **Only what is missing is added, and nothing else is touched.** These are appends. An append that
/// is not gated on what is already there produces the same argument and the same port again on every
/// run, and an argument the container carried before this ran belongs to whoever put it there.
///
/// **An argument and a published port are two halves of one thing.** The argument is what makes the
/// process inside the container listen; the published port is what makes the machine's own port
/// reach it. The argument alone gives an address nothing can connect to, the port alone gives a port
/// nothing is listening on, and neither half reports anything wrong. That is why both lists are one
/// step: they are added in one patch and the pods are replaced once.
///
/// **The comparison is against the RUNNING pods and never only against the declaration.** Patching
/// the workload changes what the next pod will be started with; on one machine it does not change
/// what is serving. The controller creates the new pod BEFORE stopping the old one, and where both
/// want the same port on the machine the new one never starts, waits for ever, and the old one goes
/// on serving with the arguments it already had. The patch reports success, the declaration in the
/// cluster really did change, and nothing about the running process did.
///
/// **So the pods are replaced here, and the order inside is the fix.** The pods stuck waiting go
/// first and without notice — they hold no port and nothing is being served by them. The ones that
/// are serving go second, with a moment to finish what they were doing. Reversed, the replacement
/// lands while a stuck pod still claims the machine's ports and the whole deadlock happens again.
///
/// **Replacing a pod interrupts what it serves.** Nothing answers on the ports it holds between the
/// moment it is deleted and the moment its replacement is up, and the requests refused in between
/// are not made again. What this step CHANGES can be taken back — the arguments and ports it added
/// are removed again and the pods replaced a second time — and the interruption itself cannot be.
/// A plan carries ONE command, so wherever the apply would both patch and delete, the dry run names
/// the DELETION — the half that cannot be taken back — and the patch that precedes it and what the
/// interruption costs are said beside it in the plan's own log.
///
/// **A workload that is not there is a skip and not a failure.** This runs after the addon that
/// installs it; on a machine where that addon is off there is nothing to patch and nothing wrong.
///
/// **Patched and not upgraded.** Where an addon owns its own release, running an upgrade against the
/// current chart conflicts on differences in the value schema and quietly does nothing. Patching the
/// running object is the supported way into an addon-managed install.
final class PatchContainerArgumentsAndPorts extends ReversibleStep<ContainerAdditions> {
  /// Makes [container] of [kind] [name] in [namespace] carry [containerArguments] and [ports].
  const PatchContainerArgumentsAndPorts({
    required this.namespace,
    required this.kind,
    required this.name,
    required this.container,
    required this.containerArguments,
    required this.ports,
    required this.rolloutTimeoutSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory PatchContainerArgumentsAndPorts.fromArguments(Arguments arguments) =>
      PatchContainerArgumentsAndPorts(
        namespace: arguments.text('namespace'),
        kind: arguments.text('kind'),
        name: arguments.text('name'),
        container: arguments.text('container'),
        containerArguments: arguments.textList('arguments'),
        ports: arguments.textList('ports'),
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
      name: 'arguments',
      kind: ArgumentKind.textList,
      describes: 'the arguments that container has to be started with',
      required: false,
      defaultValue: <String>[],
    ),
    ArgumentSpec(
      name: 'ports',
      kind: ArgumentKind.textList,
      describes:
          'the ports it publishes on the machine over TCP, each written as its name, a colon and '
          'its port',
      required: false,
      defaultValue: <String>[],
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

  /// The arguments that container has to be started with.
  final List<String> containerArguments;

  /// The ports it publishes, each written as its name, a colon and its port.
  final List<String> ports;

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

  @override
  Future<CheckResult> check(StepContext context) async {
    // A row asking for a port this cannot read must not go green: left out, the run reports
    // success and the port is never published, and nothing downstream says otherwise.
    final List<String> unreadable = <String>[
      for (final String written in ports)
        if (_PublishedPort.read(written) == null) written,
    ];
    if (unreadable.isNotEmpty) {
      return CheckResult.blocked(
        <String>[
          for (final String written in unreadable)
            '"$written" is not a port — it reads as a name, a colon and a port, such as '
                'postgres:5432',
        ].join('; '),
      );
    }
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    if (containerArguments.isEmpty && wantedPorts.isEmpty) {
      return const CheckResult.satisfied('nothing is asked of this container');
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
    final WorkloadContainer declared = workloadNow.containers[at];
    if (_missingArguments(declared.arguments).isNotEmpty ||
        _missingPorts(declared.ports, wantedPorts).isNotEmpty) {
      return const CheckResult.ready();
    }

    final List<WorkloadPod>? pods = await _target.pods(context, workloadNow.selector);
    if (pods == null) {
      return CheckResult.blocked(
        'the pods of $kind $name in $namespace could not be read, so what is actually serving '
        'cannot be compared with what the cluster declares',
      );
    }
    final List<WorkloadPod> serving = <WorkloadPod>[
      for (final WorkloadPod pod in pods)
        if (pod.phase == ContainerWorkload.running) pod,
    ];
    if (serving.isEmpty) {
      return CheckResult.satisfied(
        'no $name pod is running, so there is none serving with what it was started with',
      );
    }
    if (_lagging(serving, wantedPorts).isNotEmpty) {
      return const CheckResult.ready();
    }
    return CheckResult.satisfied(
      'the declaration and every running pod of $name carry what this program asks for',
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
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    final String? patch = _addPatch(workloadNow.containers[at], at, wantedPorts);
    final List<WorkloadPod> pods =
        await _target.pods(context, workloadNow.selector) ?? const <WorkloadPod>[];
    // The pods the apply would delete: the stuck ones unconditionally, and the serving ones that
    // lag what this program asks for — which is every serving pod the patch would leave behind.
    final List<String> podsToDelete = <String>[
      for (final WorkloadPod pod in pods)
        if (pod.phase == ContainerWorkload.pending) pod.name,
      for (final WorkloadPod pod in _lagging(pods, wantedPorts))
        if (pod.phase == ContainerWorkload.running) pod.name,
    ];
    if (podsToDelete.isEmpty) {
      return patch == null
          ? StepPlan.nothing(
              'the declaration and every running pod of $name carry what this program asks for',
            )
          : StepPlan.argv(kubectl.argv(_target.patchCommand('json', patch)));
    }
    // A plan carries one command. Of the two the apply would run, the deletion is the one whose
    // consequence cannot be taken back, so the plan names it and the log beside it says the rest.
    if (patch != null) {
      context.log.info(
        'before the deletion the declaration is patched: '
        '${kubectl.argv(_target.patchCommand('json', patch)).join(' ')}',
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
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    if (_addPatch(workloadNow.containers[at], at, wantedPorts) case final String patch) {
      await _target.mustRun(context, _target.patchCommand('json', patch));
    }
    await _target.replacePods(
      context,
      workloadNow.selector,
      (List<WorkloadPod> serving) => _lagging(serving, wantedPorts),
    );
  }

  /// What this run adds, so an undo removes exactly that and nothing else.
  ///
  /// An argument or a port the container carried BEFORE this ran was put there by something else,
  /// and taking it away would stop whatever depends on it — silently, because the container goes on
  /// running and simply stops doing one of the things it did.
  @override
  Future<ContainerAdditions> capture(StepContext context) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      // What the undo takes out is exactly what this names, so an empty list leaves the container
      // as it stands - which is what a reading nobody could take has to produce. Said out loud,
      // because an empty list otherwise reads as a container that already carried everything.
      context.log.warn(
        'what $kind $name in $namespace carried before this ran could not be read, so an undo will '
        'leave its arguments and ports alone rather than remove ones this run may not have added: '
        '$refusal',
      );
      return const ContainerAdditions(arguments: <String>[], ports: <int>[]);
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return const ContainerAdditions(arguments: <String>[], ports: <int>[]);
    }
    final WorkloadContainer declared = workloadNow.containers[at];
    return ContainerAdditions(
      arguments: _missingArguments(declared.arguments),
      ports: <int>[
        for (final _PublishedPort port in _missingPorts(declared.ports, _wantedPorts())) port.port,
      ],
    );
  }

  @override
  Future<void> undo(StepContext context, ContainerAdditions captured) async {
    final ({Workload? workload, String? refusal}) reading = await _target.read(context);
    if (reading.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final Workload? workloadNow = reading.workload;
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return;
    }
    // WHICH arguments and ports come out is what the capture decided; WHERE they sit is read now. An
    // append leaves an entry wherever the list has grown to since, so a remembered position would
    // take out whatever moved into that place. A port's position is its place in the container's
    // WHOLE ports list — entries publishing nothing count too, and the patch path resolves against
    // that list. Highest position first within each list, so removing one does not move the next
    // one out from under its own position.
    final WorkloadContainer declared = workloadNow.containers[at];
    final List<Map<String, Object>> removals = <Map<String, Object>>[
      for (final int position in _positionsOf(captured.arguments, declared.arguments))
        <String, Object>{'op': 'remove', 'path': '${containerPath(at)}/args/$position'},
      for (final int position in declared.positionsOfPorts(captured.ports))
        <String, Object>{'op': 'remove', 'path': '${containerPath(at)}/ports/$position'},
    ];
    if (removals.isEmpty) {
      return;
    }
    // A rejected removal must throw, so it is recorded as not taken back — reported as taken back,
    // the pods that come back still carry what the record says was removed.
    await _target.mustRun(context, _target.patchCommand('json', jsonEncode(removals)));
    // The declaration no longer carries them and a pod started before this does, which is the same
    // gap the apply closes — read from the other side.
    await _target.replacePods(
      context,
      workloadNow.selector,
      (List<WorkloadPod> serving) => <WorkloadPod>[
        for (final WorkloadPod pod in serving)
          if (captured.arguments.any(pod.container.arguments.contains) ||
              captured.ports.any(pod.container.ports.contains))
            pod,
      ],
    );
  }

  /// Where each of [wanted] stands in [declared], highest first and leaving out what is not there.
  static List<int> _positionsOf(List<Object> wanted, List<Object> declared) => <int>[
    for (final Object each in wanted)
      if (declared.contains(each)) declared.indexOf(each),
  ]..sort((int a, int b) => b.compareTo(a));

  /// The ports this program asks for — an entry that does not read as one has blocked the check
  /// before any caller of this runs.
  List<_PublishedPort> _wantedPorts() => <_PublishedPort>[
    for (final String written in ports)
      if (_PublishedPort.read(written) case final _PublishedPort port) port,
  ];

  /// Which of the asked-for arguments [declared] does not carry.
  List<String> _missingArguments(List<String> declared) => <String>[
    for (final String argument in containerArguments)
      if (!declared.contains(argument)) argument,
  ];

  /// Which of [wanted] is not published on [declared].
  List<_PublishedPort> _missingPorts(List<int> declared, List<_PublishedPort> wanted) =>
      <_PublishedPort>[
        for (final _PublishedPort port in wanted)
          if (!declared.contains(port.port)) port,
      ];

  /// The pods of [serving] that are missing any of it.
  List<WorkloadPod> _lagging(List<WorkloadPod> serving, List<_PublishedPort> wantedPorts) =>
      <WorkloadPod>[
        for (final WorkloadPod pod in serving)
          if (_missingArguments(pod.container.arguments).isNotEmpty ||
              _missingPorts(pod.container.ports, wantedPorts).isNotEmpty)
            pod,
      ];

  /// One patch appending what [declared] at [at] is short of, or null when it is short of nothing.
  String? _addPatch(WorkloadContainer declared, int at, List<_PublishedPort> wantedPorts) {
    final List<Map<String, Object>> additions = <Map<String, Object>>[
      for (final String argument in _missingArguments(declared.arguments))
        <String, Object>{'op': 'add', 'path': '${containerPath(at)}/args/-', 'value': argument},
      for (final _PublishedPort port in _missingPorts(declared.ports, wantedPorts))
        <String, Object>{
          'op': 'add',
          'path': '${containerPath(at)}/ports/-',
          'value': <String, Object>{
            'name': port.name,
            'containerPort': port.port,
            'hostPort': port.port,
            'protocol': 'TCP',
          },
        },
    ];
    return additions.isEmpty ? null : jsonEncode(additions);
  }
}

/// What one run of a container patch added, so its undo can remove exactly that.
final class ContainerAdditions {
  /// Records that [arguments] and [ports] were not there before the run that added them.
  const ContainerAdditions({required this.arguments, required this.ports});

  /// The arguments the run appended.
  final List<String> arguments;

  /// The ports it published, by the port number on the machine.
  final List<int> ports;
}

/// One port published on the machine: a name and the port it answers on.
final class _PublishedPort {
  const _PublishedPort(this.name, this.port);

  /// The port [written] describes, or null when it describes none.
  static _PublishedPort? read(String written) {
    final int colon = written.lastIndexOf(':');
    if (colon <= 0) {
      return null;
    }
    final String name = written.substring(0, colon).trim();
    final int? port = int.tryParse(written.substring(colon + 1).trim());
    if (name.isEmpty || port == null || port < 1 || port > 65535) {
      return null;
    }
    return _PublishedPort(name, port);
  }

  final String name;
  final int port;
}
