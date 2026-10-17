import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// One container of one workload, as the steps that patch it reach it: reading what the cluster
/// declares, reading the pods that run it, and replacing those pods once the declaration changed.
///
/// **Patching the workload changes what the next pod will be started with, and on one machine it
/// does not change what is serving.** The controller creates the new pod BEFORE stopping the old
/// one, and where both want the same port on the machine the new one never starts, waits for ever,
/// and the old one goes on serving with what it already had. So the pods are replaced here, and the
/// order inside is the fix: the pods stuck waiting go first and without notice — they hold no port
/// and nothing is being served by them — and the ones that are serving go second, with a moment to
/// finish what they were doing. Reversed, the replacement lands while a stuck pod still claims the
/// machine's ports and the whole deadlock happens again.
///
/// **Replacing a pod interrupts what it serves.** Nothing answers on the ports it holds between the
/// moment it is deleted and the moment its replacement is up, and the requests refused in between
/// are not made again.
final class ContainerWorkload {
  /// Names [container] of [kind] [name] in [namespace], reached through [kubectl].
  const ContainerWorkload({
    required this.namespace,
    required this.kind,
    required this.name,
    required this.container,
    required this.rolloutTimeoutSeconds,
    required this.kubectl,
  });

  /// The phase of a pod that is stuck waiting for something it cannot have.
  static const String pending = 'Pending';

  /// The phase of a pod that is serving.
  static const String running = 'Running';

  /// The namespace the workload runs in.
  final String namespace;

  /// The kind of workload.
  final String kind;

  /// The workload.
  final String name;

  /// The container inside it.
  final String container;

  /// How long the replacements are given.
  final int rolloutTimeoutSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// The workload as the cluster client addresses it in a rollout.
  String get workload => '$kind/$name';

  /// What deletes a pod of this namespace, up to the pod's name.
  List<String> get deleteCommand => <String>['-n', namespace, 'delete', 'pod'];

  /// What patches this workload with [patch] of the kind [type], after the words the client is
  /// invoked with.
  List<String> patchCommand(String type, String patch) => <String>[
    '-n',
    namespace,
    'patch',
    kind,
    name,
    '--type=$type',
    '-p',
    patch,
  ];

  /// The workload as the cluster holds it, null when the cluster holds no such workload, or why
  /// neither could be read.
  ///
  /// A cluster that could not be asked must not come back as the same null a cluster without the
  /// workload does, or the check answers "there is no $kind $name in $namespace, so what installs
  /// it is not up and there is nothing to patch" over it. See [Kubectl.readOne].
  Future<({Workload? workload, String? refusal})> read(StepContext context) async {
    final ({String? answer, String? refusal}) read = await kubectl.readOne(
      context,
      kind: kind,
      name: name,
      output: 'json',
      namespace: namespace,
    );
    if (read.refusal case final String refusal) {
      return (workload: null, refusal: refusal);
    }
    if (read.answer case final String json) {
      return (workload: Workload.read(_decoded(json)), refusal: null);
    }
    return (workload: null, refusal: null);
  }

  /// The pods of this workload, or null when they cannot be read.
  ///
  /// Found through the selector the workload itself declares, so the pods this compares against are
  /// the ones the cluster considers to be its. A selector written into the program beside the
  /// workload's name would be a second description of the same thing, and the two would disagree the
  /// first time one of them was edited.
  Future<List<WorkloadPod>?> pods(StepContext context, String selector) async {
    final CommandResult read = await context.shell.run(
      kubectl.observing(<String>['-n', namespace, 'get', 'pods', '-l', selector, '-o', 'json']),
    );
    if (!read.ok) {
      return null;
    }
    final Object? decoded = _decoded(read.stdout);
    if (decoded is! Map<String, Object?> || decoded['items'] is! List<Object?>) {
      return null;
    }
    return <WorkloadPod>[
      for (final Object? item in decoded['items']! as List<Object?>)
        if (WorkloadPod.read(item, container) case final WorkloadPod pod) pod,
    ];
  }

  /// Replaces the pods [choose] picks out of the ones that are serving, and waits for the workload.
  ///
  /// The stuck ones go first and unconditionally: they hold nothing, and while one of them exists
  /// the replacement cannot have the machine's ports.
  Future<void> replacePods(
    StepContext context,
    String selector,
    List<WorkloadPod> Function(List<WorkloadPod> serving) choose,
  ) async {
    final List<WorkloadPod> pods = await this.pods(context, selector) ?? const <WorkloadPod>[];
    for (final WorkloadPod pod in pods) {
      if (pod.phase != pending) {
        continue;
      }
      context.log.debug(
        '${pod.name} is stuck waiting for the ports a running pod holds — removing',
      );
      await mustRun(context, <String>[...deleteCommand, pod.name, '--grace-period=0', '--force']);
    }
    final List<WorkloadPod> serving = <WorkloadPod>[
      for (final WorkloadPod pod in pods)
        if (pod.phase == running) pod,
    ];
    for (final WorkloadPod pod in choose(serving)) {
      context.log.debug(
        '${pod.name} is serving with what it was started with — replacing it, and nothing answers '
        'on the ports it holds until its replacement is up',
      );
      await mustRun(context, <String>[...deleteCommand, pod.name, '--grace-period=10']);
    }
    await mustRun(context, <String>[
      '-n',
      namespace,
      'rollout',
      'status',
      workload,
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  /// Runs [arguments] against the cluster and throws [CommandFailed] where the client refuses.
  Future<void> mustRun(StepContext context, List<String> arguments) async {
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

  static Object? _decoded(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}

/// One workload as the cluster holds it: its containers and how its pods are found.
final class Workload {
  /// Holds [containers] and the [selector] their pods are found by.
  const Workload(this.containers, this.selector);

  /// The workload [decoded] describes, or null when it describes none a step can patch.
  static Workload? read(Object? decoded) {
    final Object? spec = _at(decoded, 'spec');
    final Object? labels = _at(_at(spec, 'selector'), 'matchLabels');
    if (labels is! Map<String, Object?>) {
      return null;
    }
    return Workload(
      <WorkloadContainer>[
        for (final Object? each in _list(_at(_at(spec, 'template'), 'spec'), 'containers'))
          if (WorkloadContainer.read(each) case final WorkloadContainer container) container,
      ],
      <String>[
        for (final MapEntry<String, Object?> label in labels.entries) '${label.key}=${label.value}',
      ].join(','),
    );
  }

  /// The containers it declares.
  final List<WorkloadContainer> containers;

  /// How the cluster itself finds this workload's pods.
  final String selector;

  /// The names it declares, for a message that says what was there instead.
  List<String> get containerNames => <String>[
    for (final WorkloadContainer container in containers) container.name,
  ];

  /// Where the container called [name] sits, or -1 when the workload declares none.
  ///
  /// A position and not the container itself, because a patch addresses a container by where it
  /// stands in the list and there is no other way to write that path.
  int positionOf(String name) {
    for (int at = 0; at < containers.length; at += 1) {
      if (containers[at].name == name) {
        return at;
      }
    }
    return -1;
  }
}

/// One container: what it is started with, what it publishes on the machine and what CPU it asks
/// for.
final class WorkloadContainer {
  /// Holds the container's [name], [arguments], published [ports], their [portPositions] and its
  /// [cpuRequest].
  const WorkloadContainer(
    this.name,
    this.arguments,
    this.ports,
    this.portPositions,
    this.cpuRequest,
  );

  /// The container [decoded] describes, or null when it describes none.
  static WorkloadContainer? read(Object? decoded) {
    final List<Object?> declaredPorts = _list(decoded, 'ports');
    final List<int> published = <int>[];
    final List<int> positions = <int>[];
    for (int at = 0; at < declaredPorts.length; at += 1) {
      if (_at(declaredPorts[at], 'hostPort') case final int number) {
        published.add(number);
        positions.add(at);
      }
    }
    final Object? cpu = _at(_at(_at(decoded, 'resources'), 'requests'), 'cpu');
    if (_at(decoded, 'name') case final String name) {
      return WorkloadContainer(
        name,
        <String>[
          for (final Object? argument in _list(decoded, 'args'))
            if (argument is String) argument,
        ],
        published,
        positions,
        cpu is String ? cpu : null,
      );
    }
    return null;
  }

  /// The CPU [written] asks for in millicores, or null where it is not a quantity of CPU.
  ///
  /// The cluster hands a quantity back in the spelling it likes — `1000m` is stored and read as
  /// `1` — so two figures are compared as millicores and never as the text they were written in.
  static int? millicores(String? written) {
    if (written == null) {
      return null;
    }
    if (written.endsWith('m')) {
      return int.tryParse(written.substring(0, written.length - 1));
    }
    final double? cores = double.tryParse(written);
    return cores == null ? null : (cores * 1000).round();
  }

  /// The container's name.
  final String name;

  /// What it is started with.
  final List<String> arguments;

  /// The ports it publishes on the machine.
  final List<int> ports;

  /// Where each of [ports] stands in the container's WHOLE ports list, position for position.
  ///
  /// The whole list and not only the published entries: entries that publish nothing sit in it
  /// too, and a patch path resolves against it — so a position counted among the published ports
  /// alone hits the wrong element as soon as such an entry sits ahead of one.
  final List<int> portPositions;

  /// The CPU it requests as the cluster wrote it, null where it requests none.
  final String? cpuRequest;

  /// [cpuRequest] in millicores, null where it requests none.
  int? get cpuRequestMillicores => millicores(cpuRequest);

  /// Where each of [wanted] is published, as [portPositions] counts it, highest first and leaving
  /// out what is not published.
  List<int> positionsOfPorts(List<int> wanted) => <int>[
    for (final int port in wanted)
      if (ports.contains(port)) portPositions[ports.indexOf(port)],
  ]..sort((int a, int b) => b.compareTo(a));
}

/// One pod, with the container inside it that a step is about.
final class WorkloadPod {
  /// A pod called [name] in [phase], running [container].
  const WorkloadPod(this.name, this.phase, this.container);

  /// The pod [decoded] describes with its container [named], or null when it has no such container.
  ///
  /// A pod of this workload running something else under the same labels is not one a step has
  /// anything to say about.
  static WorkloadPod? read(Object? decoded, String named) {
    final Object? name = _at(_at(decoded, 'metadata'), 'name');
    final Object? phase = _at(_at(decoded, 'status'), 'phase');
    if (name is! String || phase is! String) {
      return null;
    }
    for (final Object? each in _list(_at(decoded, 'spec'), 'containers')) {
      if (WorkloadContainer.read(each) case final WorkloadContainer inside
          when inside.name == named) {
        return WorkloadPod(name, phase, inside);
      }
    }
    return null;
  }

  /// The pod's name.
  final String name;

  /// Which phase it is in, which decides whether it holds a port or is waiting for one.
  final String phase;

  /// What it is actually running with.
  final WorkloadContainer container;
}

/// Where the container at [at] sits, for a patch that addresses it by position.
String containerPath(int at) => '/spec/template/spec/containers/$at';

/// What [of] holds under [key], or null where it is not an object or holds nothing there.
///
/// Everything below this line reads a document the API server composed, so every step of the way
/// down is a place the shape could be other than expected. Asking through this rather than casting
/// makes a surprising document produce a step with nothing to do instead of a crash.
Object? _at(Object? of, String key) => of is Map<String, Object?> ? of[key] : null;

/// The list [of] holds under [key], or an empty one where it holds no list there.
List<Object?> _list(Object? of, String key) {
  final Object? found = _at(of, key);
  return found is List<Object?> ? found : const <Object?>[];
}
