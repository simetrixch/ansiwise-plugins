import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

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
/// are removed again and the pods replaced a second time — and the interruption itself cannot be,
/// which is why the plan a dry run prints names the deletion.
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
      describes: 'how long the replacements are given to come up',
      required: false,
      defaultValue: 90,
    ),
  ];

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

  /// The arguments that container has to be started with.
  final List<String> containerArguments;

  /// The ports it publishes, each written as its name, a colon and its port.
  final List<String> ports;

  /// How long the replacements are given.
  final int rolloutTimeoutSeconds;

  /// The workload as the cluster client addresses it in a rollout.
  String get workload => '$kind/$name';

  @override
  Future<CheckResult> check(StepContext context) async {
    for (final String written in ports) {
      if (_PublishedPort.read(written) == null) {
        context.log.error(
          '"$written" is not a port — it reads as a name, a colon and a port, such as '
          'postgres:5432 — so it is left out',
        );
      }
    }
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    if (containerArguments.isEmpty && wantedPorts.isEmpty) {
      return const CheckResult.satisfied('nothing is asked of this container');
    }

    final _Workload? workloadNow = await _read(context);
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
    final _Container declared = workloadNow.containers[at];
    if (_missingArguments(declared.arguments).isNotEmpty ||
        _missingPorts(declared.ports, wantedPorts).isNotEmpty) {
      return const CheckResult.ready();
    }

    final List<_Pod>? pods = await _pods(context, workloadNow.selector);
    if (pods == null) {
      return CheckResult.blocked(
        'the pods of $kind $name in $namespace could not be read, so what is actually serving '
        'cannot be compared with what the cluster declares',
      );
    }
    final List<_Pod> serving = <_Pod>[
      for (final _Pod pod in pods)
        if (pod.phase == running) pod,
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
    final _Workload? workloadNow = await _read(context);
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return const StepPlan.nothing('there is no such container to patch');
    }
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    // The patch where the declaration is short of something, and otherwise the deletion — which is
    // the next command this step would run, and the one whose consequence an operator has to weigh.
    final String? patch = _addPatch(workloadNow.containers[at], at, wantedPorts);
    if (patch != null) {
      return StepPlan.argv(_patchCommand(patch));
    }
    final List<_Pod> pods = await _pods(context, workloadNow.selector) ?? const <_Pod>[];
    return StepPlan.argv(<String>[
      ..._delete,
      for (final _Pod pod in pods)
        if (pod.phase == pending) pod.name,
      for (final _Pod pod in _lagging(pods, wantedPorts))
        if (pod.phase == running) pod.name,
      '--grace-period=10',
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Workload? workloadNow = await _read(context);
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return;
    }
    final List<_PublishedPort> wantedPorts = _wantedPorts();
    if (_addPatch(workloadNow.containers[at], at, wantedPorts) case final String patch) {
      await _mustRun(context, _patchCommand(patch));
    }
    await _replacePods(
      context,
      workloadNow.selector,
      (List<_Pod> serving) => _lagging(serving, wantedPorts),
    );
  }

  /// What this run adds, so an undo removes exactly that and nothing else.
  ///
  /// An argument or a port the container carried BEFORE this ran was put there by something else,
  /// and taking it away would stop whatever depends on it — silently, because the container goes on
  /// running and simply stops doing one of the things it did.
  @override
  Future<ContainerAdditions> capture(StepContext context) async {
    final _Workload? workloadNow = await _read(context);
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return const ContainerAdditions(arguments: <String>[], ports: <int>[]);
    }
    final _Container declared = workloadNow.containers[at];
    return ContainerAdditions(
      arguments: _missingArguments(declared.arguments),
      ports: <int>[
        for (final _PublishedPort port in _missingPorts(declared.ports, _wantedPorts())) port.port,
      ],
    );
  }

  @override
  Future<void> undo(StepContext context, ContainerAdditions captured) async {
    final _Workload? workloadNow = await _read(context);
    final int at = workloadNow?.positionOf(container) ?? -1;
    if (workloadNow == null || at < 0) {
      return;
    }
    // WHICH arguments and ports come out is what the capture decided; WHERE they sit is read now. An
    // append leaves an entry wherever the list has grown to since, so a remembered position would
    // take out whatever moved into that place. Highest position first within each list, so removing
    // one does not move the next one out from under its own position.
    final _Container declared = workloadNow.containers[at];
    final List<Map<String, Object>> removals = <Map<String, Object>>[
      for (final int position in _positionsOf(captured.arguments, declared.arguments))
        <String, Object>{'op': 'remove', 'path': '${_containerPath(at)}/args/$position'},
      for (final int position in _positionsOf(captured.ports, declared.ports))
        <String, Object>{'op': 'remove', 'path': '${_containerPath(at)}/ports/$position'},
    ];
    if (removals.isEmpty) {
      return;
    }
    await context.shell.run(Command('microk8s', _patchCommand(jsonEncode(removals)).sublist(1)));
    // The declaration no longer carries them and a pod started before this does, which is the same
    // gap the apply closes — read from the other side.
    await _replacePods(
      context,
      workloadNow.selector,
      (List<_Pod> serving) => <_Pod>[
        for (final _Pod pod in serving)
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

  /// The ports this program asks for, leaving out anything that does not read as one.
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
  List<_Pod> _lagging(List<_Pod> serving, List<_PublishedPort> wantedPorts) => <_Pod>[
    for (final _Pod pod in serving)
      if (_missingArguments(pod.container.arguments).isNotEmpty ||
          _missingPorts(pod.container.ports, wantedPorts).isNotEmpty)
        pod,
  ];

  /// One patch appending what [declared] at [at] is short of, or null when it is short of nothing.
  String? _addPatch(_Container declared, int at, List<_PublishedPort> wantedPorts) {
    final List<Map<String, Object>> additions = <Map<String, Object>>[
      for (final String argument in _missingArguments(declared.arguments))
        <String, Object>{'op': 'add', 'path': '${_containerPath(at)}/args/-', 'value': argument},
      for (final _PublishedPort port in _missingPorts(declared.ports, wantedPorts))
        <String, Object>{
          'op': 'add',
          'path': '${_containerPath(at)}/ports/-',
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

  /// The command that applies [patch] to this workload.
  List<String> _patchCommand(String patch) => <String>[
    'microk8s',
    'kubectl',
    '-n',
    namespace,
    'patch',
    kind,
    name,
    '--type=json',
    '-p',
    patch,
  ];

  /// Replaces the pods [choose] picks out of the ones that are serving, and waits for the workload.
  ///
  /// The stuck ones go first and unconditionally: they hold nothing, and while one of them exists
  /// the replacement cannot have the machine's ports.
  Future<void> _replacePods(
    StepContext context,
    String selector,
    List<_Pod> Function(List<_Pod> serving) choose,
  ) async {
    final List<_Pod> pods = await _pods(context, selector) ?? const <_Pod>[];
    for (final _Pod pod in pods) {
      if (pod.phase != pending) {
        continue;
      }
      context.log.debug(
        '${pod.name} is stuck waiting for the ports a running pod holds — removing',
      );
      await _mustRun(context, <String>[..._delete, pod.name, '--grace-period=0', '--force']);
    }
    final List<_Pod> serving = <_Pod>[
      for (final _Pod pod in pods)
        if (pod.phase == running) pod,
    ];
    for (final _Pod pod in choose(serving)) {
      context.log.debug(
        '${pod.name} is serving with what it was started with — replacing it, and nothing answers '
        'on the ports it holds until its replacement is up',
      );
      await _mustRun(context, <String>[..._delete, pod.name, '--grace-period=10']);
    }
    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      namespace,
      'rollout',
      'status',
      workload,
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  /// The workload as the cluster holds it, or null when it cannot be read.
  Future<_Workload?> _read(StepContext context) async {
    final CommandResult read = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        kind,
        name,
        '-o',
        'json',
      ]),
    );
    return read.ok ? _Workload.read(_decoded(read.stdout)) : null;
  }

  /// The pods of this workload, or null when they cannot be read.
  ///
  /// Found through the selector the workload itself declares, so the pods this compares against are
  /// the ones the cluster considers to be its. A selector written into the program beside the
  /// workload's name would be a second description of the same thing, and the two would disagree the
  /// first time one of them was edited.
  Future<List<_Pod>?> _pods(StepContext context, String selector) async {
    final CommandResult read = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'pods',
        '-l',
        selector,
        '-o',
        'json',
      ]),
    );
    if (!read.ok) {
      return null;
    }
    final Object? decoded = _decoded(read.stdout);
    if (decoded is! Map<String, Object?> || decoded['items'] is! List<Object?>) {
      return null;
    }
    return <_Pod>[
      for (final Object? item in decoded['items']! as List<Object?>)
        if (_Pod.read(item, container) case final _Pod pod) pod,
    ];
  }

  List<String> get _delete => <String>['microk8s', 'kubectl', '-n', namespace, 'delete', 'pod'];

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
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

/// What one run of a container patch added, so its undo can remove exactly that.
final class ContainerAdditions {
  /// Records that [arguments] and [ports] were not there before the run that added them.
  const ContainerAdditions({required this.arguments, required this.ports});

  /// The arguments the run appended.
  final List<String> arguments;

  /// The ports it published, by the port number on the machine.
  final List<int> ports;
}

/// One workload as the cluster holds it: its containers and how its pods are found.
final class _Workload {
  const _Workload(this.containers, this.selector);

  /// The workload [decoded] describes, or null when it describes none this step can patch.
  static _Workload? read(Object? decoded) {
    final Object? spec = _at(decoded, 'spec');
    final Object? labels = _at(_at(spec, 'selector'), 'matchLabels');
    if (labels is! Map<String, Object?>) {
      return null;
    }
    return _Workload(
      <_Container>[
        for (final Object? each in _list(_at(_at(spec, 'template'), 'spec'), 'containers'))
          if (_Container.read(each) case final _Container container) container,
      ],
      <String>[
        for (final MapEntry<String, Object?> label in labels.entries) '${label.key}=${label.value}',
      ].join(','),
    );
  }

  final List<_Container> containers;

  /// How the cluster itself finds this workload's pods.
  final String selector;

  /// The names it declares, for a message that says what was there instead.
  List<String> get containerNames => <String>[
    for (final _Container container in containers) container.name,
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

/// One container: what it is started with and what it publishes on the machine.
final class _Container {
  const _Container(this.name, this.arguments, this.ports);

  /// The container [decoded] describes, or null when it describes none.
  static _Container? read(Object? decoded) {
    if (_at(decoded, 'name') case final String name) {
      return _Container(
        name,
        <String>[
          for (final Object? argument in _list(decoded, 'args'))
            if (argument is String) argument,
        ],
        <int>[
          for (final Object? port in _list(decoded, 'ports'))
            if (_at(port, 'hostPort') case final int number) number,
        ],
      );
    }
    return null;
  }

  final String name;
  final List<String> arguments;

  /// The ports it publishes on the machine.
  final List<int> ports;
}

/// One pod, with the container inside it that this step is about.
final class _Pod {
  const _Pod(this.name, this.phase, this.container);

  /// The pod [decoded] describes with its container [named], or null when it has no such container.
  ///
  /// A pod of this workload running something else under the same labels is not one this step has
  /// anything to say about.
  static _Pod? read(Object? decoded, String named) {
    final Object? name = _at(_at(decoded, 'metadata'), 'name');
    final Object? phase = _at(_at(decoded, 'status'), 'phase');
    if (name is! String || phase is! String) {
      return null;
    }
    for (final Object? each in _list(_at(decoded, 'spec'), 'containers')) {
      if (_Container.read(each) case final _Container inside when inside.name == named) {
        return _Pod(name, phase, inside);
      }
    }
    return null;
  }

  final String name;

  /// Which phase it is in, which decides whether it holds a port or is waiting for one.
  final String phase;

  /// What it is actually running with.
  final _Container container;
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

/// Where the container at [at] sits, for a patch that addresses it by position.
String _containerPath(int at) => '/spec/template/spec/containers/$at';
