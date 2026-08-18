import 'package:ansiwise_core/ansiwise_core.dart';
import 'delete_existing_cluster_issuer.dart';
import 'kubectl.dart';

/// Puts the rendered certificate issuer into the cluster.
///
/// Whether it can then actually issue anything is a different question, asked by the step after
/// this: the object is accepted long before the account behind it is registered.
final class ApplyClusterIssuer extends ReversibleStep<bool> {
  /// Applies the issuer [name] out of the file at [manifestPath].
  const ApplyClusterIssuer({
    required this.name,
    required this.manifestPath,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory ApplyClusterIssuer.fromArguments(Arguments arguments) => ApplyClusterIssuer(
    name: arguments.text('name'),
    manifestPath: arguments.text('issuer_manifest_path'),
    kubectl: Kubectl.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'the issuer every certificate on this cluster is issued by — what it is called is a '
          'fact about the installation',
    ),
    // The WHOLE path, and no base name composed here. cert-manager mandates none, so a base name
    // in this package would agree with whatever renders the file only by accident: rename it on
    // the rendering side and this step goes on looking for the old one, finds nothing, and reports
    // that the renderer has not run.
    ArgumentSpec(
      name: 'issuer_manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the file the rendered issuer stands in, as the step that renders it writes it — one '
          'value, so the writer and this cannot come to name different files',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// The manifest this step applies.
  final String manifestPath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath, elevated: elevated)) {
      return CheckResult.blocked(
        '$manifestPath is not there, so the step that renders the issuer has not run',
      );
    }
    if (await DeleteExistingClusterIssuer.exists(context, kubectl, name)) {
      return CheckResult.satisfied('$name is in the cluster');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(kubectl.argv(_apply));

  @override
  Future<void> apply(StepContext context) async {
    final Command apply = kubectl.command(_apply);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(
        argv: apply.argv,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }
  }

  /// Whether the issuer is in the cluster already.
  ///
  /// The undo deletes it, and an issuer that was there before this ran is one every certificate on
  /// the cluster is issued by — deleting it would take the account key's registration out of use
  /// while cleaning up after something else.
  @override
  Future<bool> capture(StepContext context) =>
      DeleteExistingClusterIssuer.exists(context, kubectl, name);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(kubectl.command(<String>['delete', 'clusterissuer', name]));
  }

  List<String> get _apply => <String>['apply', '-f', manifestPath];
}
