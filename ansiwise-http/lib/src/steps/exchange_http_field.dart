import 'package:ansiwise_core/ansiwise_core.dart';

import 'http_exchange.dart';

/// Sends one changing request and publishes a field of ITS OWN answer.
///
/// **Everything it sends and everything it looks for comes from its row.** The method, the address,
/// the body, the field, the answer a credential rides in — this step knows the protocol and never
/// which interface it is pointed at, so a program row supplies each of them and nothing here has a
/// default that belongs to any one product.
///
/// **Its answer is the whole of what it did**, which is what makes it an exchange rather than a
/// request that changes something. There is no address that could be asked afterwards whether this
/// happened: what would have to be read is the value the request handed back, and no address holds
/// it. So its check asks only whether the row can be sent, and the engine reads the postcondition
/// off what the row published.
///
/// **What it publishes is not a credential**, and that is the difference between this step and the
/// one beside it. A value declared secret is registered with the redactor the moment it is
/// published, and everything written from there on hides it; a value published under this step's
/// name is written into the record like any other measurement. A row carrying a credential names
/// the other step, where the declaration says so to everything that reads the program.
final class ExchangeHttpField extends ExchangeStep {
  /// Sends what [row] composes and publishes what it brings back.
  const ExchangeHttpField(this.row);

  /// Builds the step from what the program gave it.
  factory ExchangeHttpField.fromArguments(Arguments arguments) =>
      ExchangeHttpField(ExchangeRow.fromArguments(arguments));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = exchangeArguments;

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('http_exchanged_field'),
      describes: 'the value the named field of the answer to the one changing request holds',
    ),
  ];

  /// Everything this row was given, and the one request it sends.
  final ExchangeRow row;

  @override
  String get irreversibleReason => exchangeIsIrreversible;

  @override
  Future<CheckResult> check(StepContext context) async => row.readyOrBlocked(context);

  @override
  Future<StepPlan> plan(StepContext context) async => row.planned(context);

  @override
  Future<void> apply(StepContext context) async {
    final String value = await row.valueFrom(context, mayQuoteWhatCameBack: true);
    context.measurements.publish(const MeasurementName('http_exchanged_field'), value);
  }
}
