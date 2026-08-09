import 'package:ansiwise_api/ansiwise_api.dart';
import 'configure_slave_apiserver_oidc_trust.dart';
import 'delete_existing_cluster_issuer.dart';

/// Puts the rendered certificate issuer into the cluster.
///
/// Whether it can then actually issue anything is a different question, asked by the step after
/// this: the object is accepted long before the account behind it is registered.
final class ApplyClusterIssuer extends ReversibleStep<bool> {
  /// Applies the issuer [name] rendered into [stateDirectory].
  const ApplyClusterIssuer({required this.name, required this.stateDirectory});

  /// Builds the step from what the program gave it.
  factory ApplyClusterIssuer.fromArguments(Arguments arguments) => ApplyClusterIssuer(
    name: arguments.text('name'),
    stateDirectory: arguments.text('state_directory'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the issuer every certificate on this cluster is issued by',
      required: false,
      defaultValue: 'letsencrypt-prod',
    ),
    ArgumentSpec(
      name: 'state_directory',
      kind: ArgumentKind.text,
      describes: 'where this program keeps the manifests it renders',
      required: false,
      defaultValue: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
    ),
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// Where the rendered manifest is.
  final String stateDirectory;

  /// The manifest this step applies.
  String get manifestPath => '$stateDirectory/clusterissuer.yaml';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath)) {
      return CheckResult.blocked(
        '$manifestPath is not there, so the step that renders the issuer has not run',
      );
    }
    if (await DeleteExistingClusterIssuer.exists(context, name)) {
      return CheckResult.satisfied('$name is in the cluster');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult applied = await context.shell.run(Command(_argv.first, _argv.sublist(1)));
    if (!applied.ok) {
      throw CommandFailed(argv: _argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  /// Whether the issuer is in the cluster already.
  ///
  /// The undo deletes it, and an issuer that was there before this ran is one every certificate on
  /// the cluster is issued by — deleting it would take the account key's registration out of use
  /// while cleaning up after something else.
  @override
  Future<bool> capture(StepContext context) => DeleteExistingClusterIssuer.exists(context, name);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command('microk8s', <String>['kubectl', 'delete', 'clusterissuer', name]),
    );
  }

  List<String> get _argv => <String>['microk8s', 'kubectl', 'apply', '-f', manifestPath];
}
