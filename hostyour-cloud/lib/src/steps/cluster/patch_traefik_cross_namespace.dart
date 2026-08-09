import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Lets an ingress in one namespace use the shared authentication middleware in another.
///
/// The ingress controller ships locked down: a route may only name middleware that lives beside it.
/// This platform has ONE middleware doing authentication, in the identity namespace, and every route
/// that is meant to be behind a login names it. Without this flag each of those routes loses its
/// authentication reference, and it loses it silently — the route still answers, without asking
/// anybody who they are.
///
/// **The addon owns its own release, so it is patched rather than upgraded.** Running an upgrade
/// against the current chart conflicts on differences in the value schema and quietly does nothing.
/// Patching the running set is the supported way into an addon-managed install.
///
/// **A missing controller is a skip and not a failure.** This runs after the ingress addon is
/// enabled; on a machine where it is not, there is nothing to patch and nothing wrong.
final class PatchTraefikCrossNamespace extends ReversibleStep {
  /// Adds the flag to [daemonSet] in [namespace].
  const PatchTraefikCrossNamespace({required this.namespace, required this.daemonSet});

  /// Builds the step from what the program gave it.
  factory PatchTraefikCrossNamespace.fromArguments(Arguments arguments) =>
      PatchTraefikCrossNamespace(
        namespace: arguments.text('namespace'),
        daemonSet: arguments.text('daemon_set'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the ingress controller runs in',
      required: false,
      defaultValue: defaultNamespace,
    ),
    ArgumentSpec(
      name: 'daemon_set',
      kind: ArgumentKind.text,
      describes: 'the set the ingress controller runs as',
      required: false,
      defaultValue: defaultDaemonSet,
    ),
  ];

  /// Where the ingress addon puts its controller.
  static const String defaultNamespace = 'ingress';

  /// What the ingress addon calls its controller.
  static const String defaultDaemonSet = 'traefik';

  /// The flag that opens middleware references across namespaces.
  static const String flag = '--providers.kubernetescrd.allowCrossNamespace=true';

  /// The arguments the controller is declared with, or null when there is no controller.
  ///
  /// Shared with the other two steps that read the same declaration, so a missing controller is one
  /// answer in one place rather than three tests that could come to disagree.
  static Future<List<String>?> declaredArguments(
    StepContext context, {
    required String namespace,
    required String daemonSet,
  }) async {
    final CommandResult declared = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'daemonset',
        daemonSet,
        '-o',
        r'jsonpath={range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}',
      ]),
    );
    if (!declared.ok) {
      return null;
    }
    return <String>[
      for (final String line in declared.stdout.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
  }

  /// A patch that appends [value] to the controller's arguments.
  static String appendArgument(String value) => jsonEncode(<Map<String, Object>>[
    <String, Object>{
      'op': 'add',
      'path': '/spec/template/spec/containers/0/args/-',
      'value': value,
    },
  ]);

  /// The command that applies [patch] to [daemonSet] in [namespace].
  static List<String> patchCommand(String patch, String namespace, String daemonSet) => <String>[
    'microk8s',
    'kubectl',
    '-n',
    namespace,
    'patch',
    'daemonset',
    daemonSet,
    '--type=json',
    '-p',
    patch,
  ];

  /// The namespace the controller runs in.
  final String namespace;

  /// The set it runs as.
  final String daemonSet;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String>? declared = await declaredArguments(
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
    if (declared.contains(flag)) {
      return const CheckResult.satisfied('the controller already carries the flag');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(patchCommand(appendArgument(flag), namespace, daemonSet));

  @override
  Future<void> apply(StepContext context) async {
    final List<String> argv = patchCommand(appendArgument(flag), namespace, daemonSet);
    final CommandResult patched = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!patched.ok) {
      throw CommandFailed(argv: argv, exitCode: patched.exitCode, stderr: patched.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    // The position is read now rather than remembered: a patch that appended the flag at the end
    // leaves it wherever the list has grown to since, and removing by a remembered index would take
    // out whatever moved into that place.
    final List<String>? declared = await declaredArguments(
      context,
      namespace: namespace,
      daemonSet: daemonSet,
    );
    final int at = declared?.indexOf(flag) ?? -1;
    if (at < 0) {
      return;
    }
    final String patch = jsonEncode(<Map<String, Object>>[
      <String, Object>{'op': 'remove', 'path': '/spec/template/spec/containers/0/args/$at'},
    ]);
    final List<String> argv = patchCommand(patch, namespace, daemonSet);
    await context.shell.run(Command(argv.first, argv.sublist(1)));
  }
}
