import 'package:ansiwise_api/ansiwise_api.dart';
import 'install_microk8s_snap.dart';
import 'stamp_kube_proxy_cluster_cidr.dart';

/// Lets the API server accept the tokens the platform's identity provider issues.
///
/// **The claim carrying the user's name is the one that is not the address, and that is a measured
/// choice.** The API server carries a hard rule that refuses a token whenever the claim naming the
/// user is the mail address and the token does not also say the address was verified. The identity
/// provider says it was not for anybody created without a verification flow — which is the first
/// administrator and every account made in the interface — so choosing the obvious claim locks
/// exactly those people out, with a refusal that mentions nothing about verification.
///
/// **These may be written before the identity provider exists.** The API server does not fail to
/// start on an issuer it cannot reach; it simply refuses tokens until the address answers. So
/// nothing has to be ordered around the identity provider's own deployment.
final class ConfigureKubeApiserverOidc extends ReversibleStep {
  /// Points the API server at this installation's identity provider, for the client [clientId].
  const ConfigureKubeApiserverOidc({
    required this.clientId,
    required this.usernameClaim,
    required this.usernamePrefix,
    required this.groupsClaim,
    required this.groupsPrefix,
    required this.argsPath,
  });

  /// Builds the step from what the program gave it.
  factory ConfigureKubeApiserverOidc.fromArguments(Arguments arguments) =>
      ConfigureKubeApiserverOidc(
        clientId: arguments.text('client_id'),
        usernameClaim: arguments.text('username_claim'),
        usernamePrefix: arguments.text('username_prefix'),
        groupsClaim: arguments.text('groups_claim'),
        groupsPrefix: arguments.text('groups_prefix'),
        argsPath: arguments.text('args_path'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'client_id',
      kind: ArgumentKind.text,
      describes: 'the client the tokens are issued for',
      required: false,
      defaultValue: 'headlamp',
    ),
    ArgumentSpec(
      name: 'username_claim',
      kind: ArgumentKind.text,
      describes:
          'the claim carrying the user name — never the mail address, which the API server '
          'refuses unless the token also says the address was verified',
      required: false,
      defaultValue: 'preferred_username',
    ),
    ArgumentSpec(
      name: 'username_prefix',
      kind: ArgumentKind.text,
      describes: 'what every such user name is prefixed with, which access rules match on',
      required: false,
      defaultValue: 'oidc:',
    ),
    ArgumentSpec(
      name: 'groups_claim',
      kind: ArgumentKind.text,
      describes: "the claim carrying the user's groups",
      required: false,
      defaultValue: 'groups',
    ),
    ArgumentSpec(
      name: 'groups_prefix',
      kind: ArgumentKind.text,
      describes: 'what every such group name is prefixed with',
      required: false,
      defaultValue: '',
    ),
    ArgumentSpec(
      name: 'args_path',
      kind: ArgumentKind.text,
      describes: 'the file holding the arguments the API server is started with',
      required: false,
      defaultValue: defaultPath,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Which cluster holds the master part, because that is the one whose identity provider issues
  /// the tokens every cluster of an installation accepts. A slave names it; a cluster that holds
  /// the master part is it, and answers nothing.
  static const List<String> answers = <String>[roleAnswer, fqdnAnswer, masterAnswer];

  /// The name what this cluster is is answered under.
  static const String roleAnswer = 'role';

  /// The name the domain this cluster answers under is answered under.
  static const String fqdnAnswer = 'fqdn';

  /// The name the cluster holding the master part is answered under.
  static const String masterAnswer = 'master';

  /// Where the snap keeps the arguments the API server is started with.
  static const String defaultPath = '${InstallMicrok8sSnap.argumentsDirectory}/kube-apiserver';

  /// The claim the API server refuses unless the token also says the address was verified.
  static const String refusedUsernameClaim = 'email';

  /// The client they are issued for.
  final String clientId;

  /// The claim carrying the user name.
  final String usernameClaim;

  /// What user names are prefixed with.
  final String usernamePrefix;

  /// The claim carrying the groups.
  final String groupsClaim;

  /// What group names are prefixed with.
  final String groupsPrefix;

  /// The file holding the API server's arguments.
  final String argsPath;

  /// Where the tokens this cluster accepts are issued.
  ///
  /// Composed rather than answered, the way the profile stamp composes the address of Vault: an
  /// installation has ONE identity provider, it stands on the cluster holding the master part, and
  /// the path is the identity provider's own — a second answer for it would only agree with the
  /// first by accident. On a cluster that holds the master part, that cluster is the master.
  String issuerUrlIn(StepContext context) => issuerUrlFor(context, clientId);

  /// The same address for a caller that holds no instance of this step.
  ///
  /// The gate that refuses a run while the identity provider cannot be read composes the address
  /// here rather than being given one: two compositions would let the program check one address and
  /// configure another, and a cluster whose API server points at an issuer nobody measured refuses
  /// every login with a message about the token.
  static String issuerUrlFor(StepContext context, String clientId) {
    final String master = context.answers.text(roleAnswer) == masterRole
        ? context.answers.text(fqdnAnswer)
        : context.answers.text(masterAnswer);
    return 'https://idp.$master/application/o/$clientId/';
  }

  /// What a cluster holding the master part answers as its role.
  static const String masterRole = 'master';

  /// The flags this step writes, in the order they are written.
  Map<String, String> flagsIn(StepContext context) => flagsFor(issuerUrlIn(context));

  /// The same six flags for an issuer that came from somewhere else.
  ///
  /// A cluster holding the master part composes its issuer from the run's answers; a slave reads
  /// its own out of the profile, which names the cluster it belongs to. Two sources, one flag set,
  /// so the two cannot write the API server's arguments differently.
  Map<String, String> flagsFor(String issuerUrl) => <String, String>{
    '--oidc-issuer-url': issuerUrl,
    '--oidc-client-id': clientId,
    '--oidc-username-claim': usernameClaim,
    '--oidc-username-prefix': usernamePrefix,
    '--oidc-groups-claim': groupsClaim,
    '--oidc-groups-prefix': groupsPrefix,
  };

  @override
  Future<CheckResult> check(StepContext context) async {
    if (usernameClaim == refusedUsernameClaim) {
      return const CheckResult.blocked(
        'the claim carrying the user name is "$refusedUsernameClaim", and the API server refuses '
        'every token whose user-name claim is that one unless the token also says the address was '
        'verified — which the identity provider does not say for the first administrator or for any '
        'account made in the interface. Use "preferred_username".',
      );
    }
    if (!await context.files.exists(argsPath)) {
      return CheckResult.blocked(
        '$argsPath is not there — the snap writes it when it installs, so this ran before the '
        'install or against a machine whose snap is gone',
      );
    }
    final String current = await context.files.read(argsPath);
    return current == withFlags(current, flagsIn(context))
        ? CheckResult.satisfied('the API server accepts tokens issued at ${issuerUrlIn(context)}')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String current = await _current(context);
    return StepPlan.diff(argsPath, before: current, after: withFlags(current, flagsIn(context)));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String current = await _current(context);
    await context.files.write(
      argsPath,
      withFlags(current, flagsIn(context)),
      mode: StampKubeProxyClusterCidr.mode,
    );
    await StampKubeProxyClusterCidr.restartKubelite(context);
  }

  @override
  Future<void> undo(StepContext context) async {
    if (!await context.files.exists(argsPath)) {
      return;
    }
    String stripped = await context.files.read(argsPath);
    for (final String name in flagsIn(context).keys) {
      stripped = StampKubeProxyClusterCidr.withoutFlag(stripped, name);
    }
    await context.files.write(argsPath, stripped, mode: StampKubeProxyClusterCidr.mode);
    await StampKubeProxyClusterCidr.restartKubelite(context);
  }

  /// [current] carrying every one of [flags]: each replaced where it is, each appended where it is
  /// not.
  ///
  /// Shared with the step that points a cluster at another cluster's identity provider, because the
  /// two write the same six flags at the same place and a second copy of this would let them drift.
  static String withFlags(String current, Map<String, String> flags) {
    String written = current;
    for (final MapEntry<String, String> flag in flags.entries) {
      written = StampKubeProxyClusterCidr.withFlag(written, '${flag.key}=${flag.value}');
    }
    return written;
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
