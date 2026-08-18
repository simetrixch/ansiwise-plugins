import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Creates one namespace on the cluster, when it is not there.
///
/// **Nothing is put into an existing namespace by this step and nothing is taken out of one.** A
/// namespace this program needs is often also created by something else — a step that materializes
/// a secret creates the namespace it lands in — so on a normal run several of these find the
/// namespace already standing. That is the ordinary case, not a sign of anything.
///
/// **The undo is narrow because the delete is not.** Removing a namespace takes every volume claim
/// in it with it, and volumes are where stateful workloads keep the only copy of what they hold.
/// What makes it safe here is [capture]: it reads whether the namespace was already standing
/// before this step ran, and the undo removes only one that was not.
final class KubernetesNamespace extends ReversibleStep<bool> {
  /// Creates the namespace called [namespace].
  const KubernetesNamespace(this.namespace, {this.kubectl = const Kubectl()});

  /// Builds the step from what the program gave it.
  factory KubernetesNamespace.fromArguments(Arguments arguments) =>
      KubernetesNamespace(arguments.text('namespace'), kubectl: Kubectl.fromArguments(arguments));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the release of this phase is installed into',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The namespace.
  final String namespace;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async => await _isThere(context)
      ? CheckResult.satisfied('the namespace $namespace is on this cluster')
      : const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_create);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult created = await context.shell.run(
      kubectl.command(<String>['create', 'namespace', namespace]),
    );
    if (!created.ok) {
      throw CommandFailed(
        argv: _create,
        exitCode: created.exitCode,
        stdout: '',
        stderr: created.stderr,
      );
    }
  }

  /// Whether the namespace is on this cluster already.
  ///
  /// Read before the create, because after it there is no telling the two apart: a namespace this
  /// step made and one it found look the same, and the delete in the undo takes the second one's
  /// volume claims with it.
  @override
  Future<bool> capture(StepContext context) => _isThere(context);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      kubectl.command(<String>['delete', 'namespace', namespace, '--ignore-not-found']),
    );
  }

  List<String> get _create => kubectl.argv(<String>['create', 'namespace', namespace]);

  /// Whether the cluster holds this namespace.
  Future<bool> _isThere(StepContext context) async {
    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['get', 'namespace', namespace, '-o', 'name']),
    );
    return found.ok;
  }
}
