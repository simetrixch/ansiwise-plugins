import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'settings_value.dart';

/// Says whether this provider is still standing on its out-of-box flow, and at which address.
///
/// **WHAT IT IS FOR.** A provider whose bootstrap account has no password answers its out-of-box
/// flow to whoever reaches it, and the first person to walk that flow chooses the password and
/// becomes the administrator of the whole installation. Nothing else about a finished run says so:
/// the run ends, every row is accounted for, and an operator is left in front of a green record
/// with no idea that an installation is waiting for its first person — or where to go to be that
/// person. This row is the sentence, and the address is in it.
///
/// **IT MEASURES BEFORE IT SAYS ANYTHING, which is the whole reason it is a step and not a closing
/// text in a program file.** A sentence written into a file is the same sentence on a run that
/// found the provider already set up, and then the run is telling the operator something untrue
/// about the machine in front of them. So the claim and the measurement are one act: what is
/// reported is what this asked the provider one moment earlier.
///
/// **IT ASKS THE WAY THE FIRST PERSON ASKS — with no credential at all.** That is not a
/// convenience. The claim being made is precisely that a stranger reaching this address walks the
/// flow, so the ask that establishes it must carry nothing a stranger would not have. An
/// authenticated question would answer a different question.
///
/// **WHAT THE PROVIDER'S ANSWER MEANS.** The flow is walked through the provider's own executor,
/// which answers every ask with a challenge naming the stage the walker is standing on. Where the
/// flow's own policies refuse the walk — which is what they do from the moment the bootstrap
/// account has a password — the challenge is the refusal instead, and it is named as such. So the
/// three outcomes are the provider's own words and none of them is inferred from a status code:
/// the flow answered a stage, the flow answered its refusal, or something came back that this step
/// cannot read and it says that rather than guessing which of the two it was.
///
/// **THE ASK IS A READ, and the state it leaves at the other end is the provider's own bookkeeping
/// for a walk nobody continues.** No account, no password and no configuration of the provider is
/// touched by it, on this run or on any later one, which is why a dry run may ask it too.
final class ReportOutOfBoxFlow extends ObservingStep {
  /// Reports the out-of-box flow of the provider served at [subdomain] of the answered domain.
  const ReportOutOfBoxFlow({
    required this.subdomain,
    required this.domain,
    this.acceptsAnyCertificate = false,
    this.timeoutSeconds = 30,
  });

  /// Builds the step from what the program gave it.
  factory ReportOutOfBoxFlow.fromArguments(Arguments arguments) => ReportOutOfBoxFlow(
    subdomain: arguments.text('subdomain'),
    domain: SettingsValue(
      what: 'the domain the provider is served on',
      answer: arguments.optionalText('domain_answer'),
      key: arguments.optionalText('domain_key'),
      settingsPath: arguments.optionalText('settings_path'),
      runAnswer: arguments.optionalText('run_answer'),
    ),
    acceptsAnyCertificate:
        arguments.has('accepts_any_certificate') && arguments.flag('accepts_any_certificate'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
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
      name: 'accepts_any_certificate',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether a certificate that cannot be verified is accepted. Say it only where this row '
          'and the certificate come out of the same run and the answer being read is the '
          "provider's own, never for an address out on the internet — and know what it costs "
          'here: the address this row hands an operator is one a browser refuses for exactly as '
          'long as the certificate is unverifiable',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 30,
      describes: 'how long to wait for the provider to answer the one question this asks it',
    ),
  ];

  /// The slug the provider gives its own out-of-box flow.
  ///
  /// The provider's, not an installation's: every installation of this tool that has never been set
  /// up stands on this same flow, and no program row could tell anyone what it is called.
  static const String flowSlug = 'initial-setup';

  /// The component the provider names when a flow's policies refuse the walk.
  static const String refusedComponent = 'ak-stage-access-denied';

  /// The component the provider names when the walk itself broke.
  ///
  /// Read apart from [refusedComponent] because they are different answers. A refusal is the
  /// provider saying the flow is closed, which is a fact about this installation; a broken walk is
  /// the provider saying it could not run its own flow, which is a fact about the provider and
  /// tells nobody whether an account is waiting.
  static const String brokenComponent = 'ak-stage-flow-error';

  /// The label the provider is served under.
  final String subdomain;

  /// Where the domain it is served on comes from: an answer, or a key of a settings file.
  final SettingsValue domain;

  /// Whether a certificate that cannot be verified is accepted rather than ending the ask.
  final bool acceptsAnyCertificate;

  /// How long the one question is given.
  final int timeoutSeconds;

  /// The address a person walks the out-of-box flow at, on the provider served at [base].
  ///
  /// The path is the provider's own — it serves every flow it has under the same one — which is the
  /// single shape of this kind a package about the tool is allowed to know.
  String flowAddressOn(String base) => '$base/if/flow/$flowSlug/';

  /// The address that answers whether the flow may be walked at all, on the provider at [base].
  String executorAddressOn(String base) => '$base/api/v3/flows/executor/$flowSlug/?query=';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? value, String? refusal}) served = await domain.valueIn(context);
    if (served.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }

    final String base = 'https://$subdomain.${served.value}';
    final String flowAddress = flowAddressOn(base);
    final String executorAddress = executorAddressOn(base);

    final HttpAnswer answer = await context.http.send(
      HttpRequest(
        'GET',
        executorAddress,
        headers: const <String, String>{'accept': 'application/json'},
        timeout: Duration(seconds: timeoutSeconds),
        acceptsAnyCertificate: acceptsAnyCertificate,
      ),
    );
    if (!answer.ok) {
      return CheckResult.blocked(
        'the provider at $base answered ${answer.status} to $executorAddress, which is where it '
        'says whether its out-of-box flow may be walked — so nothing here knows whether this '
        'installation is waiting for its first person, and this row is saying that rather than '
        'guessing either way',
      );
    }

    final String? standingOn = _componentOf(answer.body);
    if (standingOn == null) {
      return CheckResult.blocked(
        'the provider at $base answered $executorAddress with something that names no stage, so '
        'nothing here knows whether its out-of-box flow is open — and an installation nobody holds '
        'yet is not a thing to guess at',
      );
    }

    if (standingOn == brokenComponent) {
      return CheckResult.blocked(
        'the provider at $base could not run its own out-of-box flow — it answered '
        '"$brokenComponent" — so whether this installation is waiting for its first person is '
        'exactly what nothing here can say',
      );
    }

    if (standingOn == refusedComponent) {
      // THE CASE THAT KEEPS THE OTHER ONE HONEST. A row that only ever said "waiting" would say it
      // on the second run of the same installation too, an hour after somebody took the account.
      context.log.info(
        'this installation already has its first person: the provider at $base refuses its '
        'out-of-box flow, which it does from the moment its bootstrap account has a password. '
        'Sign in at $base/ with the account that walked it.',
      );
      return CheckResult.satisfied(
        'the out-of-box flow at $flowAddress is closed, so somebody already holds this '
        "installation's administrator account",
      );
    }

    // WARN AND NOT INFO, because this is the shape the level is for: the row did its work and
    // something about the machine deserves saying. An installation standing on a public address
    // with nobody holding it is that thing, and the person who has to act on it is reading the
    // record.
    context.log.warn(
      'THIS INSTALLATION IS WAITING FOR ITS FIRST PERSON. The provider at $base answers its '
      'out-of-box flow — it is standing on "$standingOn" — so nobody holds the administrator '
      'account yet. Go to $flowAddress and choose the password there. Until somebody does, that '
      'address is open to whoever reaches it first, and every other service of this installation '
      'is reached by signing in through this provider.',
    );
    return CheckResult.satisfied(
      'the out-of-box flow at $flowAddress is open, so this installation is waiting for its first '
      'person and is unheld until one arrives',
    );
  }

  /// The stage the provider says a walker of the flow is standing on, or null where its answer
  /// names none.
  ///
  /// Null is not "no stage". It is "this step did not read one", and the two must not be the same
  /// value: every caller of this either has the provider's own word for what is going on or has to
  /// say it has nothing.
  String? _componentOf(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? component = decoded['component'];
    return component is String && component.isNotEmpty ? component : null;
  }
}
