import 'package:ansiwise_api/ansiwise_api.dart';
import '../slots.dart';
import 'microk8s.dart';
import 'set_process_flag.dart';

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
/// start on an unreachable issuer; it refuses tokens until the address answers.
final class ConfigureKubeApiserverOidc extends ReversibleStep<String?> {
  /// Points the API server at this installation's identity provider, for the client [clientId].
  const ConfigureKubeApiserverOidc({
    required this.clientId,
    required this.usernameClaim,
    required this.usernamePrefix,
    required this.groupsClaim,
    required this.groupsPrefix,
    required this.argsPath,
    this.issuer = defaultIssuer,
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
        issuer: arguments.text('issuer'),
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
    ArgumentSpec(
      name: 'issuer',
      kind: ArgumentKind.text,
      describes:
          'where the tokens are issued, written with $masterDomainSlot where the domain of the '
          'cluster holding the master part belongs and $clientSlot where the client belongs — '
          'both are filled by the run and never typed',
      required: false,
      defaultValue: defaultIssuer,
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
  static const String defaultPath = '$microk8sArgumentsDirectory/kube-apiserver';

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

  /// Where the tokens are issued, with the domain and the client still in their marked slots.
  ///
  /// The SHAPE is the row's to say; the domain is not. The run fills [masterDomainSlot] from its
  /// own answers, because an installation has ONE identity provider, it stands on the cluster
  /// holding the master part, and a second answer for its address would only agree with the first
  /// by accident.
  final String issuer;

  /// The text an issuer row writes where the domain of the cluster holding the master part belongs.
  static const String masterDomainSlot = '<master-domain>';

  /// The text an issuer row writes where the client the tokens are issued for belongs.
  ///
  /// A slot rather than a second spelling of the client's name, so the issuer and the client
  /// argument cannot disagree — the address carries the client, and a mismatch between the two
  /// refuses every login with a message about the token.
  static const String clientSlot = '<client>';

  /// The issuer as this platform deploys it, when a program names no other: the identity provider
  /// answers under `idp.` beside the other services of the master's domain, and the path below it
  /// is the provider's own URL shape for one client.
  static const String defaultIssuer = 'https://idp.$masterDomainSlot/application/o/$clientSlot/';

  /// Where the tokens this cluster accepts are issued.
  String issuerUrlIn(StepContext context) =>
      issuerUrlFor(context, issuer: issuer, clientId: clientId);

  /// The same filling for a caller that holds no instance of this step.
  ///
  /// The gate that refuses a run while the identity provider cannot be read fills the address here
  /// rather than composing one of its own: two compositions would let the program check one address
  /// and configure another, and a cluster whose API server points at an issuer nobody measured
  /// refuses every login with a message about the token. On a cluster that holds the master part,
  /// that cluster is the master.
  static String issuerUrlFor(
    StepContext context, {
    required String issuer,
    required String clientId,
  }) {
    final String master = context.answers.text(roleAnswer) == masterRole
        ? context.answers.text(fqdnAnswer)
        : context.answers.text(masterAnswer);
    return issuerWith(issuer, domain: master, clientId: clientId);
  }

  /// [issuer] with [domain] and [clientId] in its slots.
  ///
  /// Shared with the step that points a cluster at another cluster's identity provider: the domain
  /// SOURCES differ — the master's own answers there, the profile here — but the shape they fill
  /// is one, so the two cannot write different addresses from the same facts.
  static String issuerWith(String issuer, {required String domain, required String clientId}) =>
      filledSlots(issuer, <String, String>{'master-domain': domain, 'client': clientId});

  /// Why [written] cannot be used as an issuer, or null when every slot of [row] was filled.
  static String? issuerRefusal({required String row, required String written}) {
    if (leftoverSlotIn(written) case final String left) {
      return 'the issuer "$row" carries $left, and nothing in this run holds that name — an '
          'issuer row may write $masterDomainSlot and $clientSlot, and anything else would reach '
          'the API server as it stands';
    }
    return null;
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
    if (issuerRefusal(row: issuer, written: issuerUrlIn(context)) case final String why) {
      return CheckResult.blocked(why);
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
    // An issuer whose slots could not all be filled writes nothing: the check is what refuses it,
    // and a plan claiming the flags would be written with a slot still in them would be a lie.
    final bool refused = issuerRefusal(row: issuer, written: issuerUrlIn(context)) != null;
    return StepPlan.diff(
      argsPath,
      before: current,
      after: refused ? current : withFlags(current, flagsIn(context)),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    if (issuerRefusal(row: issuer, written: issuerUrlIn(context)) != null) {
      return;
    }
    final String current = await _current(context);
    await context.files.write(
      argsPath,
      withFlags(current, flagsIn(context)),
      mode: microk8sArgumentsFileMode,
    );
    await SetProcessFlag.restartKubelite(context);
  }

  /// The API server's arguments as they were, or null when the file was not there.
  ///
  /// The whole file rather than the six flags, because the undo writes it back as it stood: the
  /// snap's own arguments live in it too, and a run that unwinds does so from the newest step
  /// backwards, so each file lands on the text the step before it left.
  @override
  Future<String?> capture(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // The snap writes this file when it installs. There was none, so writing one here would leave
      // the API server started with arguments nothing on the machine put there.
      return;
    }
    await context.files.write(argsPath, captured, mode: microk8sArgumentsFileMode);
    await SetProcessFlag.restartKubelite(context);
  }

  /// [current] carrying every one of [flags]: each replaced where it is, each appended where it is
  /// not.
  ///
  /// Shared with the step that points a cluster at another cluster's identity provider, because the
  /// two write the same six flags at the same place and a second copy of this would let them drift.
  static String withFlags(String current, Map<String, String> flags) {
    String written = current;
    for (final MapEntry<String, String> flag in flags.entries) {
      written = SetProcessFlag.withFlag(written, '${flag.key}=${flag.value}');
    }
    return written;
  }

  Future<String> _current(StepContext context) async =>
      await context.files.exists(argsPath) ? context.files.read(argsPath) : '';
}
