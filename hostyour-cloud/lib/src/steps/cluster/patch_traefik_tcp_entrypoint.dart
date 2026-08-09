import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'patch_traefik_cross_namespace.dart';

/// Gives the ingress controller a listener for each plain-TCP entry point this cluster serves.
///
/// **Both halves are needed and neither works alone.** The argument tells the controller that an
/// entry point of that name exists on that port; the published port on the pod is what makes the
/// machine's own port reach it. The argument alone gives an entry point nothing can connect to; the
/// port alone gives a port nothing is listening on. A route that names such an entry point is
/// accepted either way and answers nothing.
///
/// **Each entry is added only when it is missing.** These are appends, and an append that is not
/// gated on what is already there produces the same argument and the same port twice on every run.
///
/// This is a single-node exposure: the port on the pod is the port on the machine, and nothing in
/// front of it balances anything. An empty list is a step with nothing to do.
final class PatchTraefikTcpEntrypoint extends ReversibleStep {
  /// Adds a listener for each of [entrypoints] to [daemonSet] in [namespace].
  const PatchTraefikTcpEntrypoint({
    required this.entrypoints,
    required this.namespace,
    required this.daemonSet,
  });

  /// Builds the step from what the program gave it.
  factory PatchTraefikTcpEntrypoint.fromArguments(Arguments arguments) => PatchTraefikTcpEntrypoint(
    entrypoints: arguments.textList('entrypoints'),
    namespace: arguments.text('namespace'),
    daemonSet: arguments.text('daemon_set'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'entrypoints',
      kind: ArgumentKind.textList,
      describes:
          'the plain-TCP entry points to serve, each written as its name, a colon and its '
          'port',
      required: false,
      defaultValue: <String>[],
    ),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the ingress controller runs in',
      required: false,
      defaultValue: PatchTraefikCrossNamespace.defaultNamespace,
    ),
    ArgumentSpec(
      name: 'daemon_set',
      kind: ArgumentKind.text,
      describes: 'the set the ingress controller runs as',
      required: false,
      defaultValue: PatchTraefikCrossNamespace.defaultDaemonSet,
    ),
  ];

  /// The argument that declares the entry point [name] on [port].
  static String argumentFor(String name, int port) => '--entryPoints.$name.address=:$port/tcp';

  static List<_Entrypoint> _read(List<String> written) => <_Entrypoint>[
    for (final String entry in written)
      if (_Entrypoint.read(entry) case final _Entrypoint entrypoint) entrypoint,
  ];

  /// The entry points to serve.
  final List<String> entrypoints;

  /// The namespace the controller runs in.
  final String namespace;

  /// The set it runs as.
  final String daemonSet;

  @override
  Future<CheckResult> check(StepContext context) async {
    for (final String entry in entrypoints) {
      if (_Entrypoint.read(entry) == null) {
        context.log.error(
          '"$entry" is not an entry point — it reads as a name, a colon and a port, such as '
          'postgres:5432 — so it is left out',
        );
      }
    }
    final List<_Entrypoint> wanted = _read(entrypoints);
    if (wanted.isEmpty) {
      return const CheckResult.satisfied('no plain-TCP entry point is asked for');
    }

    final List<String>? declared = await PatchTraefikCrossNamespace.declaredArguments(
      context,
      namespace: namespace,
      daemonSet: daemonSet,
    );
    if (declared == null) {
      return CheckResult.satisfied(
        'there is no $daemonSet in $namespace, so the ingress addon is not up and there is nothing '
        'to patch',
      );
    }
    final Set<int>? published = await _publishedPorts(context);
    final List<_Entrypoint> missing = _missing(wanted, declared, published ?? const <int>{});
    if (missing.isEmpty) {
      return CheckResult.satisfied(
        'every entry point is declared and published: '
        '${wanted.map((_Entrypoint e) => e.name).join(', ')}',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final List<String> declared =
        await PatchTraefikCrossNamespace.declaredArguments(
          context,
          namespace: namespace,
          daemonSet: daemonSet,
        ) ??
        const <String>[];
    final Set<int> published = await _publishedPorts(context) ?? const <int>{};
    final List<_Entrypoint> missing = _missing(_read(entrypoints), declared, published);
    return StepPlan.argv(
      PatchTraefikCrossNamespace.patchCommand(
        _patchFor(missing, declared, published),
        namespace,
        daemonSet,
      ),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final List<String> declared =
        await PatchTraefikCrossNamespace.declaredArguments(
          context,
          namespace: namespace,
          daemonSet: daemonSet,
        ) ??
        const <String>[];
    final Set<int> published = await _publishedPorts(context) ?? const <int>{};
    final List<_Entrypoint> missing = _missing(_read(entrypoints), declared, published);
    if (missing.isEmpty) {
      return;
    }
    final List<String> argv = PatchTraefikCrossNamespace.patchCommand(
      _patchFor(missing, declared, published),
      namespace,
      daemonSet,
    );
    final CommandResult patched = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!patched.ok) {
      throw CommandFailed(argv: argv, exitCode: patched.exitCode, stderr: patched.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    final List<String>? declared = await PatchTraefikCrossNamespace.declaredArguments(
      context,
      namespace: namespace,
      daemonSet: daemonSet,
    );
    if (declared == null) {
      return;
    }
    // Highest position first, so removing one does not move the next one out from under its own
    // index.
    final List<int> positions = <int>[
      for (final _Entrypoint entrypoint in _read(entrypoints))
        if (declared.contains(entrypoint.argument)) declared.indexOf(entrypoint.argument),
    ]..sort((int a, int b) => b.compareTo(a));
    if (positions.isEmpty) {
      return;
    }
    final String patch = jsonEncode(<Map<String, Object>>[
      for (final int at in positions)
        <String, Object>{'op': 'remove', 'path': '/spec/template/spec/containers/0/args/$at'},
    ]);
    final List<String> argv = PatchTraefikCrossNamespace.patchCommand(patch, namespace, daemonSet);
    await context.shell.run(Command(argv.first, argv.sublist(1)));
  }

  /// The entry points whose argument or whose published port is not there yet.
  List<_Entrypoint> _missing(List<_Entrypoint> wanted, List<String> declared, Set<int> published) =>
      <_Entrypoint>[
        for (final _Entrypoint entrypoint in wanted)
          if (!declared.contains(entrypoint.argument) || !published.contains(entrypoint.port))
            entrypoint,
      ];

  /// One patch adding every missing half of every missing entry point.
  String _patchFor(List<_Entrypoint> missing, List<String> declared, Set<int> published) =>
      jsonEncode(<Map<String, Object>>[
        for (final _Entrypoint entrypoint in missing) ...<Map<String, Object>>[
          if (!declared.contains(entrypoint.argument))
            <String, Object>{
              'op': 'add',
              'path': '/spec/template/spec/containers/0/args/-',
              'value': entrypoint.argument,
            },
          if (!published.contains(entrypoint.port))
            <String, Object>{
              'op': 'add',
              'path': '/spec/template/spec/containers/0/ports/-',
              'value': <String, Object>{
                'name': entrypoint.name,
                'containerPort': entrypoint.port,
                'hostPort': entrypoint.port,
                'protocol': 'TCP',
              },
            },
        ],
      ]);

  /// The ports the controller publishes on the machine, or null when it cannot be read.
  Future<Set<int>?> _publishedPorts(StepContext context) async {
    final CommandResult ports = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'daemonset',
        daemonSet,
        '-o',
        r'jsonpath={range .spec.template.spec.containers[0].ports[*]}{.hostPort}{"\n"}{end}',
      ]),
    );
    if (!ports.ok) {
      return null;
    }
    return <int>{
      for (final String line in ports.stdout.split('\n'))
        if (int.tryParse(line.trim()) case final int port) port,
    };
  }
}

/// One plain-TCP entry point: a name and the port it answers on.
final class _Entrypoint {
  const _Entrypoint(this.name, this.port);

  /// The entry point [written] describes, or null when it describes none.
  static _Entrypoint? read(String written) {
    final int colon = written.lastIndexOf(':');
    if (colon <= 0) {
      return null;
    }
    final String name = written.substring(0, colon).trim();
    final int? port = int.tryParse(written.substring(colon + 1).trim());
    if (name.isEmpty || port == null || port < 1 || port > 65535) {
      return null;
    }
    return _Entrypoint(name, port);
  }

  final String name;
  final int port;

  /// The argument that declares this entry point.
  String get argument => PatchTraefikTcpEntrypoint.argumentFor(name, port);
}
