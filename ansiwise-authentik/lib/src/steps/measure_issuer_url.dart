import 'package:ansiwise_core/ansiwise_core.dart';

import 'settings_value.dart';

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
  /// Publishes the issuer address of [application], served at [subdomain] of the [domain] this run
  /// holds or reads.
  const MeasureIssuerUrl({
    required this.subdomain,
    required this.domain,
    required this.application,
  });

  /// Builds the step from what the program gave it.
  factory MeasureIssuerUrl.fromArguments(Arguments arguments) => MeasureIssuerUrl(
    subdomain: arguments.text('subdomain'),
    domain: SettingsValue(
      what: 'the domain the provider is served on',
      answer: arguments.optionalText('domain_answer'),
      key: arguments.optionalText('domain_key'),
      settingsPath: arguments.optionalText('settings_path'),
      runAnswer: arguments.optionalText('run_answer'),
    ),
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
      required: false,
      describes:
          'the name of the answer holding the domain the provider is served on. Named rather than '
          'written, because a run is what knows which installation this is. Write "domain_key" '
          'instead where a settings file of the machine already carries it',
    ),
    // THE OTHER SOURCE OF THE SAME VALUE. A domain handed to a row as an answer is a COPY of what a
    // settings file of the machine already says, and a copy is what a caller gets wrong. A key
    // names the one place the value stands, so there is nothing to keep in step. Where a row names
    // both, the answer is read and the record says which key was not.
    ArgumentSpec(
      name: 'settings_path',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the settings file "domain_key" is read out of, as a path on the machine. It may carry '
          'the slot "run_answer" names. Leave it off where the domain is answered',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in '
          '"settings_path" — write "fqdn" here and a "<fqdn>" in the path is filled with the value '
          'this run holds. Leave it off where the file is named the same on every installation',
    ),
    ArgumentSpec(
      name: 'domain_key',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the key of that settings file the domain stands under, as a dotted path — each dot '
          'descends one map. Write it instead of "domain_answer", never beside it',
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

  /// Where the domain it is served on comes from: an answer, or a key of a settings file.
  final SettingsValue domain;

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
    final ({String? value, String? refusal}) served = await domain.valueIn(context);
    if (served.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = issuerFor(served.value!);
    context.measurements.publish(const MeasurementName('issuer_url'), url);
    return CheckResult.satisfied('tokens for $application are issued at $url');
  }
}
