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
/// **The address is filled by the same code that fills it for the API server, never composed
/// here.** [ConfigureKubeApiserverOidc.issuerUrlFor] is called with this row's issuer and client,
/// which therefore must be the words the configuring row writes — a gate measuring one issuer
/// while the cluster is pointed at another is green either way. Writing both values ONCE, in the
/// program's own defaults block, is what makes that agreement structural instead of a thing two
/// rows have to keep saying the same.
///
/// **WHY THIS IS NOT A TOOL PACKAGE'S STEP, and it is the question it looks like it should be.**
/// What it does is generic — an address is asked a question and the answer has to carry a named
/// field — and a step of that shape belongs in a package that owns the NETWORK as its tool, beside
/// the request and the address, not in this product. What keeps it here is the other half: the
/// address is not given, it is DERIVED from a rule only this product has. An installation has one
/// identity provider, it stands on the cluster holding the master part, and every other cluster
/// accepts the tokens it issues — so a cluster answers with its own domain and a cluster that
/// belongs to another answers with that one's. That branch is this product's, it is stated once for
/// this step and for the step that points the API server at the same address, and a package that
/// asks any address a question may not know it. Moving this as it stands would carry the rule into
/// a package that must not hold it; splitting it would need the generic step to be TOLD the address
/// by a step that measured it, which nothing can do.
///
/// **This is a gate that verifies an earlier step, and it says so.** The document does not exist
/// until the identity provider is deployed, so in the two modes that change nothing it reports what
/// it would check rather than failing on a state nobody produced. In a real run the deployment has
/// happened by the time this is asked, which is the only mode in which the question means anything.
///
/// **It reads and nothing else.** One request, no credential, no state — the same document a browser
/// fetches before it ever sees a login form.
final class IdpDiscoveryReachable extends ObservingStep {
  /// Refuses a run whose identity provider at [issuer] does not answer for the client [clientId].
  const IdpDiscoveryReachable({required this.clientId, required this.issuer});

  /// Builds the step from what the program gave it.
  factory IdpDiscoveryReachable.fromArguments(Arguments arguments) => IdpDiscoveryReachable(
    clientId: arguments.text('client_id'),
    issuer: arguments.text('issuer'),
  );

  /// What this step accepts.
  ///
  /// Neither has a default. Which client this platform issues tokens for, and the shape of the
  /// address they are issued at, are decisions of this deployment rather than of the gate — and a
  /// default here is the half of the pair that stops being read the day the other row changes, with
  /// the gate then measuring an address the cluster is not pointed at and passing either way.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'client_id',
      kind: ArgumentKind.text,
      describes:
          'the client whose issuer is measured, which has to be the one the API server is '
          'configured with — the issuer address carries it',
    ),
    ArgumentSpec(
      name: 'issuer',
      kind: ArgumentKind.text,
      describes:
          'the issuer this gate measures, with its slots still in it — it has to be the text the '
          'row configuring the API server writes, or this measures an address the cluster is not '
          'pointed at',
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
  ///
  /// The word is the discovery standard's own and not this platform's, which is why it stands here
  /// rather than in a row: every provider that answers such a document names this field, so a row
  /// that had to state it would be restating a standard on every installation.
  static const String requiredClaim = 'authorization_endpoint';

  /// Where a provider answering that standard keeps the document, under the issuer.
  static const String discoveryPath = '.well-known/openid-configuration';

  /// The client the tokens are issued for.
  final String clientId;

  /// Where the tokens are issued, with the domain and the client still in their marked slots.
  final String issuer;

  /// The issuer this run measures.
  String issuerUrlIn(StepContext context) =>
      ConfigureKubeApiserverOidc.issuerUrlFor(context, issuer: issuer, clientId: clientId);

  /// Where the discovery document stands.
  String discoveryUrlIn(StepContext context) => '${issuerUrlIn(context)}/$discoveryPath';

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (ConfigureKubeApiserverOidc.issuerRefusal(row: issuer, written: issuerUrlIn(context))
        case final String why) {
      return CheckResult.blocked(why);
    }
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
