import 'package:ansiwise_core/ansiwise_core.dart';

/// Publishes the address an application's tokens are issued at, composed the way this provider
/// composes it.
///
/// **Why this is a step and not a line in a program file.** The address is built out of parts, and a
/// program file may not build anything: the moment a file can compute, what gets debugged is the
/// file. It was a format string in one — `https://<subdomain>.<domain>/…/<application>/` — which is
/// exactly the shape the design forbids.
///
/// **Why it is not a derivation of an answer either.** The framework's derivation rules are a closed
/// set, and they leave out joining two values on purpose: a join is where an expression language
/// starts. Opening the set for this would open it for everything.
///
/// **So the composition lives in code, and this is the package it belongs to.** The path shape is
/// the PROVIDER'S own — it serves every application it stands in front of under the same one — the
/// way a store's own paths belong to the package that drives that store. What is not the provider's
/// is which application, which subdomain and which domain, and all three arrive as arguments.
///
/// It only reads. Nothing on the machine changes, so a dry run performs it and the value is there
/// for the rows that follow.
final class MeasureIssuerUrl extends ObservingStep {
  /// Publishes the issuer address of [application], served at [subdomain] of the domain the answer
  /// named by [domainAnswer] holds.
  const MeasureIssuerUrl({
    required this.subdomain,
    required this.domainAnswer,
    required this.application,
  });

  /// Builds the step from what the program gave it.
  factory MeasureIssuerUrl.fromArguments(Arguments arguments) => MeasureIssuerUrl(
    subdomain: arguments.text('subdomain'),
    domainAnswer: arguments.text('domain_answer'),
    application: arguments.text('application'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'subdomain',
      kind: ArgumentKind.text,
      describes:
          'the label this provider is served under, in front of the domain below — one '
          'installation chooses it, and this package has no opinion about which',
    ),
    ArgumentSpec(
      name: 'domain_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the domain the provider is served on. Named rather than '
          'written, because a run is what knows which installation this is',
    ),
    ArgumentSpec(
      name: 'application',
      kind: ArgumentKind.text,
      describes:
          'the slug the provider registered the application under — its own word for the thing '
          'whose tokens are wanted, and never a name this package could know',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('issuer_url'),
      describes: 'the address the named application\'s tokens are issued at',
    ),
  ];

  /// The label the provider is served under.
  final String subdomain;

  /// The name of the answer holding the domain it is served on.
  final String domainAnswer;

  /// The slug the provider registered the application under.
  final String application;

  /// The address, as this provider composes it.
  ///
  /// The trailing slash is the provider's and not decoration: what consumes this compares it against
  /// the `iss` claim the provider writes, and the two are the same string or the token is refused.
  String issuerFor(String domain) => 'https://$subdomain.$domain/application/o/$application/';

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs in
  /// every mode, so a dry run holds the value the rows after this one read — and a step that only
  /// published while applying would leave a dry run planning against a measurement nobody made.
  ///
  /// It also answers the question the engine asks after a real run: is the machine now in the state
  /// this step produces? Nothing on the machine changes here, so the honest answer is yes as soon as
  /// the value is known, and returning "there is work to do" instead is a row that reports itself
  /// unfinished on every run for ever.
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!context.answers.has(domainAnswer)) {
      return CheckResult.blocked(
        'this run holds no answer called "$domainAnswer", and it is the domain the provider is '
        'served on — without it there is no address to publish',
      );
    }
    final String domain = context.answers.text(domainAnswer);
    if (domain.isEmpty) {
      return CheckResult.blocked(
        '"$domainAnswer" was answered with nothing, so the address would name a host that is only a '
        'subdomain and a slash',
      );
    }
    final String url = issuerFor(domain);
    context.measurements.publish(const MeasurementName('issuer_url'), url);
    return CheckResult.satisfied('tokens for $application are issued at $url');
  }
}
