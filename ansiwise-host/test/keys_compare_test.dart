import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The comparison condition, over a file planted for each answer it can give.
///
/// THE INNOCENT CASES COME FIRST, and there are two of them rather than one: this condition is
/// registered under two names, so a version that always held would pass every refusal test AND look
/// right on one of the two shapes. Both directions have to be driven or neither is measured.
///
/// The three refusable shapes — a file that is not there, a key with no line, a key assigned nothing
/// — each prove it goes red on a file that says nothing it can compare.
void main() {
  const String settings = '/etc/subject/settings';
  const String here = 'THIS_ONE';
  const String there = 'THE_OTHER';

  HostMachine machineHolding(String text) =>
      HostMachine(files: FakeFiles(<String, String>{settings: text}));

  PredicateContext contextOf(HostMachine machine) =>
      machine.contextFor(const StepName('keys_compare'));

  Future<PredicateResult> askAgreeing(HostMachine machine) => const KeysAgree(
    path: settings,
    first: here,
    second: there,
    holdsWhenEqual: true,
  ).evaluate(contextOf(machine));

  Future<PredicateResult> askDiffering(HostMachine machine) => const KeysAgree(
    path: settings,
    first: here,
    second: there,
    holdsWhenEqual: false,
  ).evaluate(contextOf(machine));

  const String same = 'THIS_ONE="m1.example.com"\nTHE_OTHER="m1.example.com"\n';
  const String apart = 'THIS_ONE="m1.example.com"\nTHE_OTHER="b1.example.com"\n';

  group('the two shapes answer opposite questions about one file', () {
    test('THE INNOCENT CASE: two equal values make the agreeing shape hold', () async {
      final PredicateResult result = await askAgreeing(machineHolding(same));

      expect(result.held, isTrue);
      expect(
        result.because,
        contains('m1.example.com'),
        reason: 'a skipped step is only useful to read when the line says what was found',
      );
    });

    test('THE INNOCENT CASE: two different values make the differing shape hold', () async {
      final PredicateResult result = await askDiffering(machineHolding(apart));

      expect(result.held, isTrue);
      expect(result.because, allOf(contains('m1.example.com'), contains('b1.example.com')));
    });

    test('two equal values do NOT make the differing shape hold', () async {
      expect((await askDiffering(machineHolding(same))).held, isFalse);
    });

    test('two different values do NOT make the agreeing shape hold', () async {
      expect((await askAgreeing(machineHolding(apart))).held, isFalse);
    });

    test('the two shapes never agree with each other on one file', () async {
      // Without this, a version that answered the same way in both shapes would pass every test
      // above that drives only one of them.
      for (final String text in <String>[same, apart]) {
        final bool agreeing = (await askAgreeing(machineHolding(text))).held;
        final bool differing = (await askDiffering(machineHolding(text))).held;
        expect(agreeing, isNot(differing), reason: 'on $text');
      }
    });
  });

  group('what is refused rather than answered', () {
    test('a file that is not on the machine', () async {
      final HostMachine machine = HostMachine(files: FakeFiles(<String, String>{}));

      expect(
        () => askAgreeing(machine),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refused) => refused.because,
            'because',
            contains(settings),
          ),
        ),
      );
    });

    test('a key the file carries no line for', () async {
      final HostMachine machine = machineHolding('THIS_ONE="m1.example.com"\n');

      expect(
        () => askAgreeing(machine),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refused) => refused.because,
            'because',
            contains(there),
          ),
        ),
      );
    });

    test('a key assigned nothing at all, which is a fact nobody stated', () async {
      // The refusal that matters most. Read as a value, an empty one DIFFERS from every real value,
      // so a file nobody finished answering would take the differing branch and the installation
      // would go one way for a reason nobody wrote down.
      final HostMachine machine = machineHolding('THIS_ONE="m1.example.com"\nTHE_OTHER=""\n');

      expect(
        () => askDiffering(machine),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refused) => refused.because,
            'because',
            allOf(contains(there), contains('nothing at all')),
          ),
        ),
      );
    });

    test('two empty values are refused too, and not read as agreeing', () async {
      final HostMachine machine = machineHolding('THIS_ONE=""\nTHE_OTHER=""\n');

      expect(() => askAgreeing(machine), throwsA(isA<ConditionUnanswerable>()));
    });
  });

  group('the comparison is exact', () {
    test('values differing only in case are not the same value', () async {
      // Every rule that makes two unequal things compare equal has an edge, and an installation that
      // took a branch because of an edge nobody wrote down is what this refuses to do.
      final HostMachine machine = machineHolding(
        'THIS_ONE="M1.example.com"\nTHE_OTHER="m1.example.com"\n',
      );

      expect((await askAgreeing(machine)).held, isFalse);
    });

    test(
      'the quoting is off before the comparison, as the shell reading it would have it',
      () async {
        final HostMachine machine = machineHolding(
          'THIS_ONE="m1.example.com"\nTHE_OTHER=m1.example.com\n',
        );

        expect((await askAgreeing(machine)).held, isTrue);
      },
    );
  });
}
