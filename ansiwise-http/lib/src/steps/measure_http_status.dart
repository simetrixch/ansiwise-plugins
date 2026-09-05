import 'package:ansiwise_core/ansiwise_core.dart';

/// Asks an address once and decides on the STATUS it answered.
///
/// **Why a status and not a field of the body.** The one step of this package that waits reads a
/// field of a decoded answer, and everything outside the two-hundreds reaches it as "not yet". For
/// a service whose state IS its status that is the wrong reading in both directions at once: a
/// store that answers while it is standby, uninitialized or sealed is saying three different things,
/// each of them an answer, and a step that calls all three "not yet" waits out its whole deadline in
/// front of a machine that already said what is going on.
///
/// **THE ROW NAMES EVERY STATUS IT ACCEPTS, AND NOTHING IS IMPLICIT — not even a status in the
/// two-hundreds.** Which statuses a service answers with while it is up is a fact about that
/// service, and a default here would be this package deciding, for every caller, that a sealed store
/// is a failure. That is exactly the reading this step exists to remove. It also means a row may
/// accept a status outside the two-hundreds and refuse one inside them, which some interfaces need:
/// a 200 carrying an error page is not an answer anybody should act on.
///
/// **The status is PUBLISHED, so the distinction reaches the rows after this one.** A row that only
/// refused would tell an operator whether the service answered and nothing about which of its states
/// it is in. The value is the status as a number written out, so a later row binds
/// `{measured: http_status}` and decides for itself.
///
/// **It only measures.** The ask is a GET, so a dry run may make it, and nothing changes at either
/// end.
final class MeasureHttpStatus extends ObservingStep {
  /// Asks [url] and accepts the statuses in [accepting].
  const MeasureHttpStatus({
    required this.askingAbout,
    required this.url,
    required this.accepting,
    required this.acceptsAnyCertificate,
    required this.timeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory MeasureHttpStatus.fromArguments(Arguments arguments) => MeasureHttpStatus(
    askingAbout: arguments.text('asking_about'),
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row that has the address from an earlier
    // measurement names that measurement, and everything that examines a program before it runs has
    // to build every step — at that moment the value does not exist.
    url: arguments.optionalText('url') ?? '',
    accepting: arguments.textList('accepting'),
    acceptsAnyCertificate:
        arguments.has('accepts_any_certificate') && arguments.flag('accepts_any_certificate'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'asking_about',
      kind: ArgumentKind.text,
      describes:
          'what is being asked about, named so a refusal says which service did not answer as this '
          'row required',
    ),
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the address that is asked. A row that has it from an earlier measurement names that '
          'measurement instead, which is why this is not required: the program is examined before '
          'anything is measured, and a step that could not be built then would refuse the program',
    ),
    // REQUIRED AND WITH NO DEFAULT. Which statuses a service answers with while it is up is a fact
    // about that service and never about HTTP, so this package cannot state one for a caller.
    ArgumentSpec(
      name: 'accepting',
      kind: ArgumentKind.textList,
      describes:
          'the statuses this row counts as an answer, written out as numbers. Nothing is accepted '
          'that is not named here, a status in the two-hundreds included — a service that answers '
          'while it is standby, uninitialized or sealed says so with a status of its own, and which '
          'of those this row is content with is the row\'s to say',
    ),
    ArgumentSpec(
      name: 'accepts_any_certificate',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether a certificate that cannot be verified is accepted. Say it only where this row '
          'and the certificate come out of the same run and the address being asked is the '
          "installation's own, never for an address out on the internet",
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      required: false,
      defaultValue: 30,
      describes: 'how long the one ask is given',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('http_status'),
      describes: 'the status the address answered, written out as a number',
    ),
  ];

  /// What is being asked about, as a refusal names it.
  final String askingAbout;

  /// The address that is asked.
  final String url;

  /// The statuses this row counts as an answer.
  final List<String> accepting;

  /// Whether a certificate that cannot be verified is accepted.
  final bool acceptsAnyCertificate;

  /// How long the one ask is given.
  final int timeoutSeconds;

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs in
  /// every mode, so a dry run holds the value the rows after this one read — and a step that only
  /// published while applying would leave a dry run planning against a measurement nobody made.
  @override
  Future<CheckResult> check(StepContext context) async {
    if (url.isEmpty) {
      return const CheckResult.blocked(
        'this row holds no address — write one under "url", or take it from a measurement an '
        'earlier row publishes',
      );
    }
    if (accepting.isEmpty) {
      return CheckResult.blocked(
        'this row accepts no status at all, so nothing about $askingAbout could ever satisfy it — '
        'name under "accepting" every status this service answers with while it is up',
      );
    }

    final HttpAnswer answer;
    try {
      answer = await context.http.send(
        HttpRequest(
          'GET',
          url,
          timeout: Duration(seconds: timeoutSeconds),
          acceptsAnyCertificate: acceptsAnyCertificate,
        ),
      );
    } on Object catch (why) {
      // NOT AN ACCEPTED STATUS AND NOT A REFUSED ONE. Nothing answered at all, so there is no status
      // to publish and no status to judge — and a step that folded this into "a status this row does
      // not accept" would tell an operator to look at a service that never heard the request.
      return CheckResult.blocked(
        '$url could not be asked about $askingAbout, so nothing said anything: '
        '${'$why'.split('\n').map((String line) => line.trim()).join(' ')}',
      );
    }

    final String status = '${answer.status}';
    if (!accepting.contains(status)) {
      return CheckResult.blocked(
        '$url answered $status about $askingAbout, and this row accepts '
        '${accepting.join(', ')}',
      );
    }
    context.measurements.publish(const MeasurementName('http_status'), status);
    return CheckResult.satisfied('$url answered $status about $askingAbout');
  }
}
