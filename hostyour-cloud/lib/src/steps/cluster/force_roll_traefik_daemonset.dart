import 'package:ansiwise_api/ansiwise_api.dart';
import 'patch_traefik_cross_namespace.dart';
import 'patch_traefik_tcp_entrypoint.dart';

/// Replaces an ingress controller pod that is still running with the arguments it was started with.
///
/// **The deadlock this exists for happens only on one machine, which is every machine here.** The
/// controller is replaced by creating the new pod BEFORE the old one is stopped. On a cluster of
/// several machines that is fine. On one machine both pods want the same ports on the machine, so
/// the new pod never starts, waits for ever, and the old one goes on serving traffic with the
/// arguments it already had. Every patch before this reports success, the declaration in the cluster
/// really did change, and nothing about the running controller did.
///
/// **So the comparison is against the RUNNING pod and never against the declaration.** What the
/// declaration says is what the patches wrote; what the pod says is what is actually serving.
///
/// **The order inside is the fix.** The pods that are stuck waiting go first and without notice —
/// they hold no port and nothing is being served by them. The running one goes second, with a moment
/// to finish what it was doing. Reversed, the replacement lands while a stuck pod still claims the
/// machine's ports and the whole deadlock happens again.
final class ForceRollTraefikDaemonset extends IrreversibleStep {
  /// Replaces the running controller pod when it lags what [entrypoints] and the flag require.
  const ForceRollTraefikDaemonset({
    required this.entrypoints,
    required this.namespace,
    required this.daemonSet,
    required this.rolloutTimeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory ForceRollTraefikDaemonset.fromArguments(Arguments arguments) => ForceRollTraefikDaemonset(
    entrypoints: arguments.textList('entrypoints'),
    namespace: arguments.text('namespace'),
    daemonSet: arguments.text('daemon_set'),
    rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'entrypoints',
      kind: ArgumentKind.textList,
      describes: 'the plain-TCP entry points the running controller has to be serving',
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
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the replacement is given to come up',
      required: false,
      defaultValue: 90,
    ),
  ];

  /// How the controller's pods are found.
  static const String selector = 'app.kubernetes.io/name=traefik';

  /// The plain-TCP entry points the running controller has to be serving.
  final List<String> entrypoints;

  /// The namespace the controller runs in.
  final String namespace;

  /// The set it runs as.
  final String daemonSet;

  /// How long the replacement is given.
  final int rolloutTimeoutSeconds;

  @override
  String get irreversibleReason =>
      'the pod serving every ingress on this cluster is deleted, and nothing answers on ports 80 and '
      '443 until its replacement is up — the requests refused in between are not made again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, List<String>>? running = await _podArguments(context, 'Running');
    if (running == null) {
      return CheckResult.satisfied(
        'the pods of $daemonSet in $namespace could not be read, so the ingress addon is not up and '
        'there is nothing running to replace',
      );
    }
    if (running.isEmpty) {
      return CheckResult.satisfied('no $daemonSet pod is running, so there is none to replace');
    }
    final List<String> lagging = _lagging(running);
    if (lagging.isEmpty) {
      return const CheckResult.satisfied(
        'the running controller carries everything the declaration requires',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final Map<String, List<String>> running =
        await _podArguments(context, 'Running') ?? const <String, List<String>>{};
    return StepPlan.argv(<String>[
      'microk8s',
      'kubectl',
      '-n',
      namespace,
      'delete',
      'pod',
      ..._lagging(running),
      '--grace-period=10',
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    // The stuck ones first and with no notice: they hold nothing, and while one of them exists the
    // replacement cannot have the machine's ports.
    final Map<String, List<String>> pending =
        await _podArguments(context, 'Pending') ?? const <String, List<String>>{};
    for (final String pod in pending.keys) {
      context.log.debug('$pod is stuck waiting for the ports the running pod holds — removing it');
      await _mustRun(context, <String>[..._delete, pod, '--grace-period=0', '--force']);
    }

    final Map<String, List<String>> running =
        await _podArguments(context, 'Running') ?? const <String, List<String>>{};
    for (final String pod in _lagging(running)) {
      context.log.debug('$pod is serving with the arguments it was started with — replacing it');
      await _mustRun(context, <String>[..._delete, pod, '--grace-period=10']);
    }

    await _mustRun(context, <String>[
      'microk8s',
      'kubectl',
      '-n',
      namespace,
      'rollout',
      'status',
      'daemonset/$daemonSet',
      '--timeout=${rolloutTimeoutSeconds}s',
    ]);
  }

  /// Every argument the running controller has to carry.
  List<String> _required() => <String>[
    PatchTraefikCrossNamespace.flag,
    for (final String entry in entrypoints)
      if (_entrypointArgument(entry) case final String argument) argument,
  ];

  /// The pods of [running] that are missing any of them.
  List<String> _lagging(Map<String, List<String>> running) => <String>[
    for (final MapEntry<String, List<String>> pod in running.entries)
      if (_required().any((String argument) => !pod.value.contains(argument))) pod.key,
  ];

  /// The argument [entry] asks for, or null when it is not an entry point.
  static String? _entrypointArgument(String entry) {
    final int colon = entry.lastIndexOf(':');
    if (colon <= 0) {
      return null;
    }
    final int? port = int.tryParse(entry.substring(colon + 1).trim());
    if (port == null) {
      return null;
    }
    return PatchTraefikTcpEntrypoint.argumentFor(entry.substring(0, colon).trim(), port);
  }

  /// The arguments each pod in [phase] is running with, or null when the pods cannot be read.
  Future<Map<String, List<String>>?> _podArguments(StepContext context, String phase) async {
    final CommandResult pods = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'pods',
        '-l',
        selector,
        '--field-selector=status.phase=$phase',
        '-o',
        r'jsonpath={range .items[*]}{.metadata.name}{"\t"}'
            r'{range .spec.containers[0].args[*]}{@}{" "}{end}{"\n"}{end}',
      ]),
    );
    if (!pods.ok) {
      return null;
    }
    final Map<String, List<String>> found = <String, List<String>>{};
    for (final String line in pods.stdout.split('\n')) {
      final int tab = line.indexOf('\t');
      if (tab <= 0) {
        continue;
      }
      found[line.substring(0, tab).trim()] = <String>[
        for (final String argument in line.substring(tab + 1).split(' '))
          if (argument.trim().isNotEmpty) argument.trim(),
      ];
    }
    return found;
  }

  List<String> get _delete => <String>['microk8s', 'kubectl', '-n', namespace, 'delete', 'pod'];

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
