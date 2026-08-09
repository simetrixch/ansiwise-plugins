import 'package:yaml/yaml.dart';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'configure_kube_apiserver_oidc.dart';
import 'stamp_kube_proxy_cluster_cidr.dart';

/// Makes a cluster that has no identity provider of its own accept the one on the cluster that has.
///
/// **Why this exists as a separate step.** The identity provider is deployed on exactly one cluster.
/// The shared dashboard runs there, signs people in there, and forwards the token it got to
/// whichever cluster the chosen credentials point at — so every OTHER cluster's API server needs the
/// same two things the deploying cluster gets for itself: the flags naming the issuer, and the rule
/// that makes the administrators' group an administrator here.
///
/// **The address of that cluster is derived and never typed.** It is read out of the one value the
/// role stamp writes into the installation's own profile, so a cluster cannot end up trusting an
/// identity provider that nothing else on it points at. On a branch the role stamp has not touched
/// yet there is nothing to derive, and this correctly does nothing rather than guessing.
final class ConfigureSlaveApiserverOidcTrust extends ReversibleStep {
  /// Points a machine at the identity provider of the cluster its profile names.
  const ConfigureSlaveApiserverOidcTrust({
    required this.repository,
    required this.clientId,
    required this.adminGroup,
    required this.bindingName,
    required this.stateDirectory,
    required this.argsPath,
  });

  /// Builds the step from what the program gave it.
  factory ConfigureSlaveApiserverOidcTrust.fromArguments(Arguments arguments) =>
      ConfigureSlaveApiserverOidcTrust(
        repository: arguments.text('repository'),
        clientId: arguments.text('client_id'),
        adminGroup: arguments.text('admin_group'),
        bindingName: arguments.text('binding_name'),
        stateDirectory: arguments.text('state_directory'),
        argsPath: arguments.text('args_path'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation is generated in, which carries the cluster's own "
          'profile',
    ),
    ArgumentSpec(
      name: 'client_id',
      kind: ArgumentKind.text,
      describes: 'the client the tokens are issued for',
      required: false,
      defaultValue: 'headlamp',
    ),
    ArgumentSpec(
      name: 'admin_group',
      kind: ArgumentKind.text,
      describes: 'the group in the identity provider whose members administer this cluster',
      required: false,
      defaultValue: 'authentik Admins',
    ),
    ArgumentSpec(
      name: 'binding_name',
      kind: ArgumentKind.text,
      describes: 'what the rule granting that group its rights is called',
      required: false,
      defaultValue: 'authentik-admins-cluster-admin',
    ),
    ArgumentSpec(
      name: 'state_directory',
      kind: ArgumentKind.text,
      describes: 'where this program keeps the manifests it renders',
      required: false,
      defaultValue: defaultStateDirectory,
    ),
    ArgumentSpec(
      name: 'args_path',
      kind: ArgumentKind.text,
      describes: 'the file holding the arguments the API server is started with',
      required: false,
      defaultValue: ConfigureKubeApiserverOidc.defaultPath,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// What this machine is decides whether it trusts another cluster at all, and that is one
  /// installation's fact rather than a line of a program file that ships to every installation.
  static const List<String> answers = <String>[roleAnswer];

  /// The name the role is answered under.
  static const String roleAnswer = 'role';

  /// The role of a machine that deploys no identity provider of its own.
  static const String trustingRole = 'slave';

  /// Where this program keeps what it renders.
  static const String defaultStateDirectory = '/var/snap/microk8s/common/hostyour';

  /// `0644` — a rendered manifest that carries nothing secret.
  static const int manifestMode = 0x1a4;

  /// The checkout this installation is generated in.
  final String repository;

  /// The client the tokens are issued for.
  final String clientId;

  /// The group whose members administer this cluster.
  final String adminGroup;

  /// What the rule granting it is called.
  final String bindingName;

  /// Where the rendered manifest goes.
  final String stateDirectory;

  /// The file holding the API server's arguments.
  final String argsPath;

  /// The profile the address is derived from.
  String get profilePath => '$repository/cluster/profile.yaml';

  /// The manifest this step renders.
  String get manifestPath => '$stateDirectory/$bindingName.yaml';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String role = context.answers.text(roleAnswer);
    if (role != trustingRole) {
      return CheckResult.satisfied(
        'this machine is a $role, and a cluster that deploys the identity provider points its own '
        'API server at it',
      );
    }
    final String? issuer = await issuerFrom(context, profilePath, clientId);
    if (issuer == null) {
      return CheckResult.satisfied(
        '$profilePath names no address to derive the identity provider from yet, so there is nothing '
        'to trust — the role stamp writes it',
      );
    }
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — the snap writes it when it installs, so this ran before the '
        'install or against a machine whose snap is gone',
      );
    }

    final String current = await context.files.read(argsPath);
    final List<String> missing = <String>[
      if (current != ConfigureKubeApiserverOidc.withFlags(current, _flags(issuer)))
        'the API server does not accept tokens issued at $issuer',
      if (!await _bindingExists(context)) '$adminGroup is not an administrator of this cluster',
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied('this cluster trusts the identity provider at $issuer');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? issuer = await issuerFrom(context, profilePath, clientId);
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    return StepPlan.diff(
      argsPath,
      before: current,
      after: issuer == null
          ? current
          : ConfigureKubeApiserverOidc.withFlags(current, _flags(issuer)),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? issuer = await issuerFrom(context, profilePath, clientId);
    if (issuer == null) {
      return;
    }
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    await context.files.write(
      argsPath,
      ConfigureKubeApiserverOidc.withFlags(current, _flags(issuer)),
      mode: StampKubeProxyClusterCidr.mode,
    );
    await StampKubeProxyClusterCidr.restartKubelite(context);

    await context.files.createDirectory(stateDirectory, mode: 0x1ed);
    await context.files.write(manifestPath, _binding, mode: manifestMode);
    final List<String> argv = <String>['microk8s', 'kubectl', 'apply', '-f', manifestPath];
    final CommandResult applied = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!applied.ok) {
      throw CommandFailed(argv: argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    await context.shell.run(
      Command('microk8s', <String>['kubectl', 'delete', 'clusterrolebinding', bindingName]),
    );
    if (!await context.files.exists(argsPath)) {
      return;
    }
    String stripped = await context.files.read(argsPath);
    for (final String name in _flags('').keys) {
      stripped = StampKubeProxyClusterCidr.withoutFlag(stripped, name);
    }
    await context.files.write(argsPath, stripped, mode: StampKubeProxyClusterCidr.mode);
    await StampKubeProxyClusterCidr.restartKubelite(context);
  }

  /// The address tokens are issued at, derived from the profile at [profilePath].
  ///
  /// The profile names the cluster holding the platform's shared services by the address of one of
  /// them, and the identity provider sits beside it under the same domain. Reading it from there is
  /// what keeps a cluster from trusting an identity provider nothing else on it points at.
  static Future<String?> issuerFrom(
    StepContext context,
    String profilePath,
    String clientId,
  ) async {
    if (!await context.files.exists(profilePath)) {
      return null;
    }
    final YamlNode profile;
    try {
      profile = loadYamlNode(await context.files.read(profilePath));
    } on YamlException {
      return null;
    }
    YamlNode? at = profile;
    for (final String key in <String>['global', 'vaultUrl']) {
      if (at case final YamlMap map) {
        at = map.nodes[key];
        continue;
      }
      return null;
    }
    if (at?.value case final String url) {
      final int dot = url.indexOf('.');
      final int scheme = url.indexOf('://');
      if (dot < 0 || scheme < 0 || dot < scheme) {
        return null;
      }
      final String domain = url.substring(dot + 1).split('/').first.trim();
      return domain.isEmpty ? null : 'https://idp.$domain/application/o/$clientId/';
    }
    return null;
  }

  Map<String, String> _flags(String issuer) => ConfigureKubeApiserverOidc(
    clientId: clientId,
    usernameClaim: 'preferred_username',
    usernamePrefix: 'oidc:',
    groupsClaim: 'groups',
    groupsPrefix: '',
    argsPath: argsPath,
  ).flagsFor(issuer);

  Future<bool> _bindingExists(StepContext context) async {
    final CommandResult binding = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        'get',
        'clusterrolebinding',
        bindingName,
        '-o',
        'jsonpath={.metadata.name}',
      ]),
    );
    return binding.ok && binding.trimmed == bindingName;
  }

  String get _binding =>
      '# The group the identity provider puts administrators in administers this cluster too.\n'
      'apiVersion: rbac.authorization.k8s.io/v1\n'
      'kind: ClusterRoleBinding\n'
      'metadata:\n'
      '  name: $bindingName\n'
      'roleRef:\n'
      '  apiGroup: rbac.authorization.k8s.io\n'
      '  kind: ClusterRole\n'
      '  name: cluster-admin\n'
      'subjects:\n'
      '  - apiGroup: rbac.authorization.k8s.io\n'
      '    kind: Group\n'
      '    name: "$adminGroup"\n';
}
