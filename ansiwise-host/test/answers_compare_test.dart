import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Whether two answers of one run carry the same value.
///
/// **What this replaces, and why it could not stay where it was.** A program row used to write
/// `stated_when: {answer: a, equals_answer: b}` — a comparison living in a file beside the registered
/// conditions, and the moment a file can compare it can compare anything. Registered, the comparison
/// is a class with these probes, and the file writes one bare name.
///
/// **Why it reads the RUN and not a file, which is what the other two conditions do.** A file is
/// written by a step, and a step runs after the answers are validated. The question this answers —
/// did this answer have to be given at all — is asked BEFORE the first step, so it cannot wait for a
/// file that does not exist yet.
void main() {
  const StepName under = StepName('answer_values_agree');

  PredicateContext runHolding(Map<String, Object> answers) =>
      HostMachine().contextFor(under, Arguments.none, Arguments(answers));

  const AnswersAgree agreeing = AnswersAgree(first: 'one', second: 'other', holdsWhenEqual: true);
  const AnswersAgree differing = AnswersAgree(first: 'one', second: 'other', holdsWhenEqual: false);

  group('two answers that say the same thing', () {
    test('the agreeing shape holds, and says what both are', () async {
      final PredicateResult result = await agreeing.evaluate(
        runHolding(<String, Object>{'one': 'same.example.com', 'other': 'same.example.com'}),
      );

      expect(result.held, isTrue);
      expect(result.because, contains('same.example.com'));
    });

    test('THE INNOCENT NEIGHBOUR: the differing shape does not', () async {
      // Without both shapes a program file would need a `not:`, and an operator in a program file is
      // where it starts being a language.
      final PredicateResult result = await differing.evaluate(
        runHolding(<String, Object>{'one': 'same.example.com', 'other': 'same.example.com'}),
      );

      expect(result.held, isFalse);
    });
  });

  group('two answers that say different things', () {
    test('the differing shape holds, and names both values', () async {
      final PredicateResult result = await differing.evaluate(
        runHolding(<String, Object>{'one': 'first.example.com', 'other': 'second.example.com'}),
      );

      expect(result.held, isTrue);
      expect(result.because, allOf(contains('first.example.com'), contains('second.example.com')));
    });

    test('THE INNOCENT NEIGHBOUR: the agreeing shape does not', () async {
      final PredicateResult result = await agreeing.evaluate(
        runHolding(<String, Object>{'one': 'first.example.com', 'other': 'second.example.com'}),
      );

      expect(result.held, isFalse);
    });
  });

  group('what it refuses rather than deciding', () {
    test('an answer the run does not hold', () async {
      // Refused and not answered either way: deciding here would turn a question nobody was asked
      // into a decision about the installation, and the run would take a branch nobody wrote down.
      await expectLater(
        agreeing.evaluate(runHolding(<String, Object>{'one': 'first.example.com'})),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable each) => each.because,
            'because',
            contains('other'),
          ),
        ),
      );
    });

    test('an answer given as nothing', () async {
      // An empty answer is not a value that differs from another. It is a fact nobody stated.
      await expectLater(
        differing.evaluate(runHolding(<String, Object>{'one': '', 'other': 'second.example.com'})),
        throwsA(isA<ConditionUnanswerable>()),
      );
    });
  });
}
