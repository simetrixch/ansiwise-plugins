import 'package:ansiwise_api/ansiwise_api.dart';

/// Evaluates a list of answer names and publishes the first non-empty value as a measurement.
///
/// **Why a measurement?** Because the framework already supports injecting measurements
/// using `{measured: name}` anywhere in a YAML row.
///
/// **The fallback order.** The answers are evaluated in the order they are listed.
/// If `role` is `master`, `master` is usually empty, and `fqdn` contains the domain.
/// So `answers: [master, fqdn]` will correctly pick the `master` cluster domain when
/// this is a slave, and the `fqdn` when this is the master.
final class MeasureCoalesced extends ObservingStep {
  /// Publishes coalesced_value based on the first non-empty value from [answers].
  const MeasureCoalesced({
    required this.answers,
    required this.format,
  });

  /// Builds the step from what the program gave it.
  factory MeasureCoalesced.fromArguments(Arguments arguments) {
    final String rawAnswers = arguments.text('answers');
    final List<String> parsedAnswers = rawAnswers.split(',').map((String s) => s.trim()).toList();

    return MeasureCoalesced(
      answers: parsedAnswers,
      format: arguments.optionalText('format') ?? '<value>',
    );
  }

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'answers',
      kind: ArgumentKind.text,
      describes: 'a comma-separated list of answer names to evaluate in order',
    ),
    ArgumentSpec(
      name: 'format',
      kind: ArgumentKind.text,
      describes: 'an optional format string using <value> to interpolate the picked answer into',
      required: false,
      defaultValue: '<value>',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('coalesced_value'),
      describes: 'the first non-empty value evaluated from answers',
    ),
  ];

  /// The list of answer names to evaluate.
  final List<String> answers;

  /// The format string using `<value>` to interpolate the picked answer into.
  final String format;

  @override
  Future<CheckResult> check(StepContext context) async {
    for (final String answerName in answers) {
      if (context.answers.has(answerName)) {
        final String rawValue = context.answers.text(answerName).trim();
        if (rawValue.isNotEmpty) {
          final String value = format.replaceAll('<value>', rawValue);
          context.measurements.publish(const MeasurementName('coalesced_value'), value);
          return CheckResult.satisfied('measured coalesced_value as "$value" from answer "$answerName"');
        }
      }
    }

    return CheckResult.blocked(
      'none of the answers (${answers.join(', ')}) produced a non-empty value, so coalesced_value could not be measured',
    );
  }
}
