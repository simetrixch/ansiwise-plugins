import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The two shapes of the one reading this package carries, over a file planted for each answer it
/// can give.
///
/// FIVE PLANTED CASES AND THE INNOCENT ONE FIRST. The four refusable shapes — a key that is absent,
/// a file that is not there, a value that is neither word, a key assigned nothing — each prove this
/// condition goes red on a file that says nothing it can read. The two that ARE answers prove it
/// goes green on one that does. Without the innocent case a condition that refused everything would
/// pass all four, and a check nothing can satisfy measures nothing.
void main() {
  _slots();
  _theOtherShape();

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

/// Which file the condition reads, when the path carries a slot the run fills.
///
/// **The defect this measures.** An installation's configuration is read ONCE, before a program is
/// resolved, and it holds no answers — the axis is an answer, supplied per run. So a binding naming
/// one value of that axis literally is right on exactly one kind of installation and refuses every
/// other before its first step. Measured on a real installation: three conditions bound to the file
/// of one stage, on a machine carrying the file of another, which left two of the three stages that
/// product ships unable to run its last program at all.
void _slots() {
  group('a path carrying a slot', () {
    // INVENTED, like every other fixture here. A path naming one product's checkout would be that
    // product's fact living in a package that has to serve any of them — and the check that says so
    // reports it, which is how this fixture came to be written twice.
    const KeyIsTrue bound = KeyIsTrue(
      path: '/etc/subject/settings.<stage>',
      key: 'SUBJECT_ON',
      runAnswer: 'stage',
    );

    test('is filled from the answer the row names', () {
      expect(
        bound.pathIn(const Arguments(<String, Object>{'stage': 'second'})),
        '/etc/subject/settings.second',
      );
      expect(
        bound.pathIn(const Arguments(<String, Object>{'stage': 'first'})),
        '/etc/subject/settings.first',
        reason: 'the same binding serves every stage, which is the whole point of the slot',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a path with no slot is left exactly as written', () {
      const KeyIsTrue plain = KeyIsTrue(path: '/etc/subject/settings', key: 'SUBJECT_ON');

      expect(
        plain.pathIn(const Arguments(<String, Object>{'stage': 'prod'})),
        '/etc/subject/settings',
        reason: 'a row naming no answer must not have its path rewritten behind it',
      );
    });
  });
}

/// The shape bound as `key_is_false`, planted the same way as the one above.
///
/// THREE CASES, AND THE ONE IN THE MIDDLE IS WHAT A NEGATION WOULD HAVE GOT WRONG. A `not:` behind
/// `when:` holds wherever the true shape does not, which includes every file this condition refuses
/// to read — so a switch nobody set would have run the rows meant for a switch set to false. The
/// third case plants exactly that file and requires a refusal, not an answer.
void _theOtherShape() {
  const String settings = '/etc/subject/settings';
  const String subjectKey = 'SUBJECT_ON';

  Future<PredicateResult> askFalse(String text) =>
      const KeyIsTrue(path: settings, key: subjectKey, holdsWhenTrue: false).evaluate(
        HostMachine(
          files: FakeFiles(<String, String>{settings: text}),
        ).contextFor(const StepName('key_is_false')),
      );

  group('the shape that reads for false', () {
    test('THE INNOCENT CASE: the key holds false, and the condition holds', () async {
      final PredicateResult result = await askFalse('$subjectKey="false"\n');

      expect(result.held, isTrue);
      expect(
        result.because,
        allOf(contains(settings), contains(subjectKey), contains('false')),
        reason: 'the plan an operator reads has to say which word switched these rows on',
      );
    });

    test('the key holds true, and the condition does not hold', () async {
      final PredicateResult result = await askFalse('$subjectKey="true"\n');

      expect(result.held, isFalse);
      expect(
        result.because,
        contains('true'),
        reason: 'a row skipped here was skipped because the file said true, and the record says so',
      );
    });

    test('WHAT A NEGATION WOULD HAVE ANSWERED: an unreadable value is refused, not held', () async {
      await expectLater(
        askFalse('$subjectKey="ture"\n'),
        throwsA(isA<ConditionUnanswerable>()),
        reason:
            'the false shape refuses everywhere the true shape refuses; a negation would have held '
            'here and run the rows for a switch the operator never set',
      );
    });
  });
}
