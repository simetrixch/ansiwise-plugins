import 'package:ansiwise_api/ansiwise_api.dart';
import '../cluster/configure_kube_apiserver_oidc.dart';

/// Refuses to go on while the identity provider's discovery document cannot be read.
///
/// Every consumer of the identity provider validates it live before it will store a configuration:
/// the secret store fetches the discovery document while its login method is being configured, the
/// reconciler does the same, and each of them fails at that moment with a message about its own
/// configuration rather than about the address. So the address is measured once, here, and named as
/// what it is.
///
/// **The address is composed by the step that configures the API server, and not by this one.** The
/// two are the same address by construction — [ConfigureKubeApiserverOidc.issuerUrlFor] is called
/// here — because a gate given its own address checks one issuer while the cluster is pointed at
/// another, and the run is green either way.
///
/// **This is a gate that verifies an earlier step, and it says so.** The document does not exist
/// until the identity provider is deployed, so in the two modes that change nothing it reports what
/// it would check rather than failing on a state nobody produced. In a real run the deployment has
/// happened by the time this is asked, which is the only mode in which the question means anything.
///
/// **It reads and nothing else.** One request, no credential, no state — the same document a browser
/// fetches before it ever sees a login form.
final class IdpDiscoveryReachable extends ObservingStep {
  /// Refuses a run whose identity provider does not answer for the client [clientId].
  const IdpDiscoveryReachable({required this.clientId});

  /// Builds the step from what the program gave it.
  factory IdpDiscoveryReachable.fromArguments(Arguments arguments) =>
      IdpDiscoveryReachable(clientId: arguments.text('client_id'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'client_id',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: 'headlamp',
      describes:
          'the client whose issuer is measured, which has to be the one the API server is '
          'configured with — the issuer address carries it',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The three the issuer is composed from, the same three the step that configures the API server
  /// reads: an installation has one identity provider and it stands on the cluster holding the
  /// master part.
  static const List<String> answers = <String>[
    ConfigureKubeApiserverOidc.roleAnswer,
    ConfigureKubeApiserverOidc.fqdnAnswer,
    ConfigureKubeApiserverOidc.masterAnswer,
  ];

  /// The name of the field a discovery document cannot be one without.
  static const String requiredClaim = 'authorization_endpoint';

  /// The client the tokens are issued for.
  final String clientId;

  /// The issuer this run measures.
  String issuerUrlIn(StepContext context) =>
      ConfigureKubeApiserverOidc.issuerUrlFor(context, clientId);

  /// Where the discovery document stands.
  String discoveryUrlIn(StepContext context) =>
      '${issuerUrlIn(context)}/.well-known/openid-configuration';

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String discoveryUrl = discoveryUrlIn(context);

    // A `GET`, so the framework derives on its own that this changes nothing — which is what lets a
    // dry run send it and still be a dry run.
    final HttpAnswer answer = await context.http.send(
      HttpRequest('GET', discoveryUrl, timeout: const Duration(seconds: 15)),
    );

    if (!answer.ok) {
      return CheckResult.blocked(
        '$discoveryUrl answered ${answer.status}. Every consumer of the identity provider fetches '
        'this document while it is being configured and fails there with a message about its own '
        'configuration, so the address is measured here instead',
      );
    }
    return answer.body.contains(requiredClaim)
        ? CheckResult.satisfied('$discoveryUrl answers and names its $requiredClaim')
        : CheckResult.blocked(
            '$discoveryUrl answered ${answer.status} and the body carries no $requiredClaim, so '
            'something other than the identity provider is answering at that address',
          );
  }
}
