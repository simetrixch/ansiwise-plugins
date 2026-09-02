import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Takes the certificate issuer away so the next steps build it again from what this run renders.
///
/// Only when the operator asks for it. An issuer that is there and working is what every certificate
/// on the cluster depends on, and rebuilding it for no reason is a change with a real risk and no
/// gain.
final class RemoveExistingClusterIssuer extends IrreversibleStep {
  /// Deletes the issuer [name] when [force] is set.
  const RemoveExistingClusterIssuer({
    required this.name,
    required this.force,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory RemoveExistingClusterIssuer.fromArguments(Arguments arguments) =>
      RemoveExistingClusterIssuer(
        name: arguments.text('name'),
        force: arguments.flag('force'),
        kubectl: Kubectl.fromArguments(arguments),
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
    ArgumentSpec(
      name: 'force',
      kind: ArgumentKind.flag,
      describes: 'whether an issuer that is already there is taken away and built again',
      required: false,
      defaultValue: false,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// Whether the operator asked for it to be rebuilt.
  final bool force;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  String get irreversibleReason =>
      'the issuer object is gone. The account key in the secret of the same name stays behind, so an '
      'issuer built again carries on with the registration that key belongs to — a genuinely fresh '
      'registration means deleting that secret as well, and then the old registration is what cannot '
      'be recovered';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!force) {
      return const CheckResult.satisfied(
        'a rebuild was not asked for, so an issuer that is already there is left alone',
      );
    }
    final ({bool? there, String? refusal}) live = await exists(context, kubectl, name);
    if (live.refusal case final String refusal) {
      return CheckResult.blocked(
        '$refusal - and this row was told to rebuild it, which is a rebuild reported as done over '
        'an issuer that may still be standing',
      );
    }
    if (!live.there!) {
      return CheckResult.satisfied('there is no $name to take away');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(kubectl.argv(_delete));

  @override
  Future<void> apply(StepContext context) async {
    final Command delete = kubectl.command(_delete);
    final CommandResult deleted = await context.shell.run(delete);
    if (!deleted.ok) {
      throw CommandFailed(
        argv: delete.argv,
        exitCode: deleted.exitCode,
        stdout: '',
        stderr: deleted.stderr,
      );
    }
  }

  /// Whether the issuer [name] is in the cluster, or why that could not be read.
  ///
  /// Shared with the step that applies it, so both ask the same question of the cluster.
  ///
  /// A cluster that could not be asked must not come back as the same false a cluster without the
  /// issuer does, or the check above answers "there is no $name to take away" over it - on a row an
  /// operator reaches by asking for a rebuild, so what they are told is that the rebuild happened.
  /// See [Kubectl.readOne].
  static Future<({bool? there, String? refusal})> exists(
    StepContext context,
    Kubectl kubectl,
    String name,
  ) async {
    final ({String? answer, String? refusal}) issuer = await kubectl.readOne(
      context,
      kind: 'clusterissuer',
      name: name,
      output: 'jsonpath={.metadata.name}',
    );
    if (issuer.refusal case final String refusal) {
      return (there: null, refusal: refusal);
    }
    return (there: issuer.answer?.trim() == name, refusal: null);
  }

  List<String> get _delete => <String>['delete', 'clusterissuer', name];
}
