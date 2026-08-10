import 'package:ansiwise_api/ansiwise_api.dart';
import '../gitops/cluster_profile.dart';
import '../kubectl.dart';
import 'configure_kube_apiserver_oidc.dart';
import 'microk8s.dart';
import 'set_process_flag.dart';

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
final class ConfigureSlaveApiserverOidcTrust
    extends ReversibleStep<({String? args, bool binding})> {
  /// Points a machine at the identity provider of the cluster its profile names.
  const ConfigureSlaveApiserverOidcTrust({
    required this.repository,
    required this.clientId,
    required this.adminGroup,
    required this.bindingName,
    required this.stateDirectory,
    required this.argsPath,
    this.issuer = ConfigureKubeApiserverOidc.defaultIssuer,
    this.kubectl = const Kubectl(),
    this.layout = const VaultLayout(),
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
        issuer: arguments.text('issuer'),
        kubectl: Kubectl.fromArguments(arguments),
        layout: VaultLayout.fromArguments(arguments),
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
    ArgumentSpec(
      name: 'issuer',
      kind: ArgumentKind.text,
      describes:
          'where the tokens are issued, written with '
          '${ConfigureKubeApiserverOidc.masterDomainSlot} where the domain of the cluster holding '
          'the master part belongs and ${ConfigureKubeApiserverOidc.clientSlot} where the client '
          'belongs — on this step the domain is derived from where the secret store answers, '
          'never typed',
      required: false,
      defaultValue: ConfigureKubeApiserverOidc.defaultIssuer,
    ),
    Kubectl.argument,
    ...VaultLayout.arguments,
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

  /// Where the tokens are issued, with the domain and the client still in their marked slots.
  final String issuer;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Where the secret store's own facts stand, and under which names.
  ///
  /// The same layout the vault family declares, because this reads the same file for the same
  /// value. A step that took it from a literal while the family took it from a row would open a
  /// path the operator never configured — and this one answers SATISFIED when it finds nothing, so
  /// the run would come back green with a slave that trusts no identity provider.
  final VaultLayout layout;

  /// The profile the address is derived from.
  String get profilePath => '$repository/${layout.profile}';

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
    final ClusterProfile store = await clusterProfileFrom(context, repository, layout: layout);
    if (store.refusal case final String refusal) {
      // BLOCKED AND NOT SATISFIED. A profile that cannot be read at all, or that carries no address
      // under the name this run was told to look under, is not "the stamp has not run yet" — it is
      // a question nothing answered. Reported as satisfied, the run comes back green with a slave
      // whose API server accepts no token from the identity provider, and the message blames a
      // stamp that already ran.
      return CheckResult.blocked(refusal);
    }
    final String? issuerUrl = issuerUrlFrom(store.url);
    if (issuerUrl == null) {
      return CheckResult.blocked(
        '$profilePath carries ${store.url} under ${layout.urlKey}, and no identity provider can be '
        'derived from it — the address the secret store answers at is what gives the domain',
      );
    }
    if (ConfigureKubeApiserverOidc.issuerRefusal(row: issuer, written: issuerUrl)
        case final String why) {
      return CheckResult.blocked(why);
    }
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — the snap writes it when it installs, so this ran before the '
        'install or against a machine whose snap is gone',
      );
    }

    final String current = await context.files.read(argsPath);
    final List<String> missing = <String>[
      if (current != ConfigureKubeApiserverOidc.withFlags(current, _flags(issuerUrl)))
        'the API server does not accept tokens issued at $issuerUrl',
      if (!await _bindingExists(context)) '$adminGroup is not an administrator of this cluster',
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied('this cluster trusts the identity provider at $issuerUrl');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? issuerUrl = issuerUrlFrom(
      (await clusterProfileFrom(context, repository, layout: layout)).url,
    );
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    // An issuer that cannot be derived, or whose slots could not all be filled, writes nothing:
    // the check is what refuses it, and a plan claiming otherwise would be a lie.
    final bool unusable =
        issuerUrl == null ||
        ConfigureKubeApiserverOidc.issuerRefusal(row: issuer, written: issuerUrl) != null;
    return StepPlan.diff(
      argsPath,
      before: current,
      after: unusable ? current : ConfigureKubeApiserverOidc.withFlags(current, _flags(issuerUrl)),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? issuerUrl = issuerUrlFrom(
      (await clusterProfileFrom(context, repository, layout: layout)).url,
    );
    if (issuerUrl == null ||
        ConfigureKubeApiserverOidc.issuerRefusal(row: issuer, written: issuerUrl) != null) {
      return;
    }
    final String current = await context.files.exists(argsPath)
        ? await context.files.read(argsPath)
        : '';
    await context.files.write(
      argsPath,
      ConfigureKubeApiserverOidc.withFlags(current, _flags(issuerUrl)),
      mode: microk8sArgumentsFileMode,
    );
    await SetProcessFlag.restartKubelite(context);

    await context.files.createDirectory(stateDirectory, mode: 0x1ed);
    await context.files.write(manifestPath, _binding, mode: manifestMode);
    final Command apply = kubectl.command(<String>['apply', '-f', manifestPath]);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(argv: apply.argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  /// The two things this step changes, read before it changes either.
  ///
  /// [ConfigureSlaveApiserverOidcTrust.argsPath] as it stood, or null when the file was not there,
  /// and whether the rule granting the administrators' group its rights was already in the cluster.
  /// Both are needed: the file is written back as it was, and a rule that was there before this ran
  /// is one somebody else applied — deleting it would take the cluster's administrators away while
  /// the run is cleaning up after something else.
  @override
  Future<({String? args, bool binding})> capture(StepContext context) async => (
    args: await context.files.exists(argsPath) ? await context.files.read(argsPath) : null,
    binding: await _bindingExists(context),
  );

  @override
  Future<void> undo(StepContext context, ({String? args, bool binding}) captured) async {
    if (!captured.binding) {
      await context.shell.run(
        kubectl.command(<String>['delete', 'clusterrolebinding', bindingName]),
      );
    }
    if (captured.args case final String args) {
      await context.files.write(argsPath, args, mode: microk8sArgumentsFileMode);
      await SetProcessFlag.restartKubelite(context);
    }
  }

  /// The domain of the cluster holding the master part, derived from where the secret store
  /// answers, or null where [vaultUrl] gives none.
  ///
  /// The profile names that cluster by the address of one of its shared services, and the identity
  /// provider sits beside it under the same domain — the store answers at `vault.<domain>`, so the
  /// address of one gives the other. It is DERIVED and never read from a key of its own: a second
  /// key would be a second thing to keep in step with the first. Reading it from there is what
  /// keeps a cluster from trusting an identity provider nothing else on it points at.
  ///
  /// The profile is not parsed here. It is read once, by the reader the whole vault family uses, so
  /// where it stands and what its keys are called is a program row's to say in one place rather than
  /// in every step that happens to need a value out of it.
  static String? masterDomainFrom(String? vaultUrl) {
    if (vaultUrl == null) {
      return null;
    }
    final int dot = vaultUrl.indexOf('.');
    final int scheme = vaultUrl.indexOf('://');
    if (dot < 0 || scheme < 0 || dot < scheme) {
      return null;
    }
    final String domain = vaultUrl.substring(dot + 1).split('/').first.trim();
    return domain.isEmpty ? null : domain;
  }

  /// The identity provider this cluster trusts: [issuer] with the derived domain and the client in
  /// its slots, or null where no domain can be derived.
  ///
  /// The filling is the one the master's own step uses, so the two cannot write different
  /// addresses from the same shape — only the SOURCE of the domain differs, and that difference is
  /// the whole of this step.
  String? issuerUrlFrom(String? vaultUrl) {
    final String? domain = masterDomainFrom(vaultUrl);
    return domain == null
        ? null
        : ConfigureKubeApiserverOidc.issuerWith(issuer, domain: domain, clientId: clientId);
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
      kubectl.observing(<String>[
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
