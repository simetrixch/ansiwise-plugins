import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_exchange.dart';

/// Sends one changing request and publishes a field of its own answer AS A CREDENTIAL.
///
/// **The step beside this one, with one difference that changes everything about the record.** What
/// it publishes is declared secret, so the run's own sink registers the value with the redactor at
/// the moment it is published — before it is stored, before any later row is built with it, and
/// before any line the engine writes about a row that takes it. From then on every surface of the
/// run hides it.
///
/// **So this step must never echo the value in a message of its own**, and there is nothing the
/// redactor could do about it if it did. Registration reaches FORWARD: a line written before the
/// publish is in the record as it was written, and nothing can be taken out of it. The value goes
/// from the answer to `publish` and nowhere else — not into a log line, not into a refusal, not into
/// a failure reason. Where the other end refuses, what is said names the method, the address and the
/// status, and the body it came with is deliberately not repeated: at that moment nothing is
/// registered and a body written there would be a body written in the clear.
///
/// **Why it is a KIND and not a flag on a row.** A row that could declare a value secret is a row
/// that could forget to, and a credential nobody marked is one nothing hides. The step knows what it
/// asked the other end to make; the file does not.
final class ExchangeHttpSecret extends ExchangeStep {
  /// Sends what [row] composes and publishes what it brings back, as a credential.
  const ExchangeHttpSecret(this.row);

  /// Builds the step from what the program gave it.
  factory ExchangeHttpSecret.fromArguments(Arguments arguments) =>
      ExchangeHttpSecret(ExchangeRow.fromArguments(arguments));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = exchangeArguments;

  /// What this step publishes, declared secret in code because a row may not decide it.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('http_exchanged_secret'),
      describes: 'the credential the named field of the answer to the one changing request holds',
      secret: true,
    ),
  ];

  /// Everything this row was given, and the one request it sends.
  final ExchangeRow row;

  @override
  String get irreversibleReason => exchangeIsIrreversible;

  @override
  Future<CheckResult> check(StepContext context) => row.readyOrBlocked(context);

  @override
  Future<StepPlan> plan(StepContext context) => row.planned(context);

  @override
  Future<void> apply(StepContext context) async {
    final String value = await row.valueFrom(context, mayQuoteWhatCameBack: false);
    // PUBLISHED AS THE FIRST THING DONE WITH IT, and nothing is done with it afterwards. This call
    // is where the redactor learns the value; a line written before it keeps what it was written
    // with, on every surface, for good.
    context.measurements.publish(const MeasurementName('http_exchanged_secret'), value);
  }
}
