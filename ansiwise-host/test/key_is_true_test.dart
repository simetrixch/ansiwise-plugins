import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The one condition this package carries, over a file planted for each answer it can give.
///
/// FIVE PLANTED CASES AND THE INNOCENT ONE FIRST. The four refusable shapes — a key that is absent,
/// a file that is not there, a value that is neither word, a key assigned nothing — each prove this
/// condition goes red on a file that says nothing it can read. The two that ARE answers prove it
/// goes green on one that does. Without the innocent case a condition that refused everything would
/// pass all four, and a check nothing can satisfy measures nothing.
void main() {
  const String settings = '/etc/subject/settings';
  const String subjectKey = 'SUBJECT_ON';

  HostMachine machineHolding(String text) =>
      HostMachine(files: FakeFiles(<String, String>{settings: text}));

  PredicateContext contextOf(HostMachine machine) =>
      machine.contextFor(const StepName('key_is_true'));

  Future<PredicateResult> ask(HostMachine machine) =>
      const KeyIsTrue(path: settings, key: subjectKey).evaluate(contextOf(machine));

  group('the file says what it says', () {
    test('the innocent case: the key holds true, and the condition holds', () async {
      final PredicateResult result = await ask(
        machineHolding('# switched on for this installation\n$subjectKey="true"\nOTHER="false"\n'),
      );

      expect(result.held, isTrue);
      expect(
        result.because,
        allOf(contains(settings), contains(subjectKey), contains('true')),
        reason: 'the plan an operator reads carries this line beside every step it switched on',
      );
    });

    test('the key holds false, and the condition does not hold', () async {
      final PredicateResult result = await ask(machineHolding('$subjectKey="false"\n'));

      expect(result.held, isFalse);
      expect(result.because, allOf(contains(settings), contains(subjectKey), contains('false')));
    });

    test('an unquoted value reads the same as a quoted one', () async {
      // The shell that sources this file reads both the same way, and a file written by hand
      // carries the bare word. A condition that saw a difference would answer one thing about a
      // file two readers agree on.
      expect((await ask(machineHolding('$subjectKey=true\n'))).held, isTrue);
    });

    test('a trailing comment is not part of the value', () async {
      expect((await ask(machineHolding('$subjectKey=true # turned on last week\n'))).held, isTrue);
    });
  });

  group('planted defects — each one refuses instead of answering false', () {
    test('a value that is a typo', () async {
      await expectLater(
        ask(machineHolding('$subjectKey="ture"\n')),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains('ture'), contains(subjectKey), contains(settings)),
          ),
        ),
        reason:
            'read as false, a typo switches off every step waiting on this key and the run stays '
            'green — which is the whole failure this condition exists to stop',
      );
    });

    for (final String spelling in <String>['TRUE', 'yes', '1', 'on', 'True']) {
      test('"$spelling" is not another way of writing true', () async {
        await expectLater(
          ask(machineHolding('$subjectKey="$spelling"\n')),
          throwsA(isA<ConditionUnanswerable>()),
          reason:
              'a set of accepted spellings is a table with an outside, and everything outside it '
              'reads as false',
        );
      });
    }

    test('a key that is absent', () async {
      await expectLater(
        ask(machineHolding('SOMETHING_ELSE="true"\n')),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains(subjectKey), contains(settings)),
          ),
        ),
      );
    });

    test('a key that is only commented out', () async {
      await expectLater(
        ask(machineHolding('# $subjectKey="true"\n')),
        throwsA(isA<ConditionUnanswerable>()),
        reason: 'a suggestion an operator may switch on is not an answer they gave',
      );
    });

    test('a key that is assigned nothing at all', () async {
      await expectLater(
        ask(machineHolding('$subjectKey=""\n')),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            contains('nothing at all'),
          ),
        ),
        reason: 'this is the shape a file ships in before anybody has answered it',
      );
    });

    test('a file that is missing', () async {
      final HostMachine empty = HostMachine(files: FakeFiles());

      await expectLater(
        const KeyIsTrue(path: settings, key: subjectKey).evaluate(contextOf(empty)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains(settings), contains('has to be there before the run starts')),
          ),
        ),
        reason:
            'every condition is measured before the first step, so a file a program would have '
            'written does not exist yet and never will by the time this is asked',
      );
    });
  });

  group('the registry entry', () {
    test('carries the condition as generic, so nothing may name it until it is bound', () {
      final RegisteredPredicate entry = hostConditions[const PredicateName('key_is_true')]!;

      expect(entry.takesArguments, isTrue);
      expect(
        entry.predicate,
        isNull,
        reason: 'an unbound generic condition is not a condition yet',
      );
      expect(
        entry.arguments.map((ArgumentSpec spec) => spec.name),
        containsAll(<String>['file', 'key']),
      );
    });

    test('binding it under a name gives back a condition that reads what it was told', () async {
      final RegisteredPredicate bound = hostConditions[const PredicateName('key_is_true')]!.boundTo(
        const PredicateName('subject_enabled'),
        const Arguments(<String, Object>{'file': settings, 'key': subjectKey}),
      );
      final HostMachine machine = machineHolding('$subjectKey="true"\n');

      expect(
        (await bound.predicate!.evaluate(contextOf(machine))).held,
        isTrue,
        reason: 'this is the whole path from a plugin entry to the word a program row writes',
      );
    });
  });
}
