import 'package:ansiwise_api/ansiwise_api.dart';

/// Creates one namespace on the cluster, when it is not there.
///
/// **Nothing is put into an existing namespace by this step and nothing is taken out of one.** The
/// namespaces this program needs are also created by other things — the identity provider writes its
/// consumers' OIDC secrets into theirs before the release that owns each one is installed — so on a
/// normal run several of these find the namespace already standing. That is the ordinary case, not a
/// sign of anything.
///
/// **The undo is narrow because the delete is not.** Removing a namespace takes every volume claim
/// in it with it, and the volumes are where Vault's storage and the identity provider's database
/// live. What makes it safe here is that the undo only ever runs for a namespace this step itself
/// created moments earlier, which by its own check held nothing.
final class KubernetesNamespace extends ReversibleStep {
  /// Creates the namespace called [namespace].
  const KubernetesNamespace(this.namespace);

  /// Builds the step from what the program gave it.
  factory KubernetesNamespace.fromArguments(Arguments arguments) =>
      KubernetesNamespace(arguments.text('namespace'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the release of this phase is installed into',
    ),
  ];

  /// The namespace.
  final String namespace;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult found = await context.shell.run(
      Command.observing('kubectl', <String>['get', 'namespace', namespace, '-o', 'name']),
    );
    return found.ok
        ? CheckResult.satisfied('the namespace $namespace is on this cluster')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_create);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult created = await context.shell.run(Command('kubectl', _create.sublist(1)));
    if (!created.ok) {
      throw CommandFailed(argv: _create, exitCode: created.exitCode, stderr: created.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    await context.shell.run(
      Command('kubectl', <String>['delete', 'namespace', namespace, '--ignore-not-found']),
    );
  }

  List<String> get _create => <String>['kubectl', 'create', 'namespace', namespace];
}
