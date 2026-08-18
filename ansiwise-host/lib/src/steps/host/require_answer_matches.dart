import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a run where an answer does not match a regular expression.
///
/// **The step reads the answer and evaluates it.** This ensures that a domain name
/// or a role answer has the exact format required, before any network is touched.
final class RequireAnswerMatches extends ObservingStep {
  /// Refuses the run if the answer named [answerName] does not match [pattern].
  const RequireAnswerMatches({
    required this.answerName,
    required this.pattern,
    required this.refusal,
  });

  /// Builds the step from what the program gave it.
  factory RequireAnswerMatches.fromArguments(Arguments arguments) => RequireAnswerMatches(
    answerName: arguments.text('answer'),
    pattern: arguments.text('pattern'),
    refusal: arguments.text('refusal'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'answer',
      kind: ArgumentKind.answerName,
      describes: 'the name of the answer this run holds',
    ),
    ArgumentSpec(
      name: 'pattern',
      kind: ArgumentKind.text,
      describes: 'the regular expression the answer is expected to match',
    ),
    ArgumentSpec(
      name: 'refusal',
      kind: ArgumentKind.text,
      describes: 'the reason presented to the user when the answer does not match',
    ),
  ];

  /// The name of the answer to check.
  final String answerName;

  /// The regular expression pattern.
  final String pattern;

  /// The refusal message.
  final String refusal;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String value = context.answers.text(answerName);
    final RegExp regExp = RegExp(pattern);

    if (!regExp.hasMatch(value)) {
      return CheckResult.blocked(
        'the answer for $answerName ($value) does not match the required pattern: $refusal',
      );
    }

    return const CheckResult.satisfied('the answer matches the required pattern');
  }
}
