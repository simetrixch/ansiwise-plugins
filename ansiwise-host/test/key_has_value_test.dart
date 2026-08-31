import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A key that NAMES a thing, read for one name and for anything but it.
///
/// The subject is a choice among named things rather than a truth: which authority a cluster issues
/// its certificates from. Both shapes are planted, and so are the two files that are not an answer at
/// all — because a condition that refuses nothing switches rows on for reasons nobody wrote down.
void main() {
  const String settings = '/etc/subject/settings';
  const String key = 'SUBJECT_AUTHORITY';
  const String wanted = 'subject-public';

  Future<PredicateResult> ask(String text, {required bool matching}) =>
      KeyHasValue(path: settings, key: key, value: wanted, holdsWhenEqual: matching).evaluate(
        HostMachine(
          files: FakeFiles(<String, String>{settings: text}),
        ).contextFor(const StepName('key_has_value')),
      );

  group('reading for one name', () {
    test('THE INNOCENT CASE: the key carries it, and the condition holds', () async {
      final PredicateResult result = await ask('$key="$wanted"\n', matching: true);

      expect(result.held, isTrue);
      expect(
        result.because,
        allOf(contains(settings), contains(key), contains(wanted)),
        reason: 'the plan an operator reads has to say which name switched these rows on',
      );
    });

    test('another name does not hold, and the record says which one stood there', () async {
      final PredicateResult result = await ask('$key="subject-local"\n', matching: true);

      expect(result.held, isFalse);
      expect(result.because, contains('subject-local'));
    });

    test('a key assigned nothing does not hold, and is NOT refused', () async {
      // The file a fill row has not reached yet is a file that says this cluster does not carry the
      // stated name — which is a fact about it, not a gap in it. Refusing here would stop the very
      // run whose job is to fill it.
      final PredicateResult result = await ask('$key=\n', matching: true);

      expect(result.held, isFalse);
      expect(result.because, contains('nothing at all'));
    });
  });

  group('reading for anything but that name', () {
    test('THE INNOCENT CASE: another name holds', () async {
      final PredicateResult result = await ask('$key="subject-local"\n', matching: false);

      expect(result.held, isTrue);
    });

    test('the stated name does not hold', () async {
      final PredicateResult result = await ask('$key="$wanted"\n', matching: false);

      expect(result.held, isFalse);
    });
  });

  group('what is not an answer is refused, in both shapes', () {
    test('a file that is not on this machine', () async {
      for (final bool shape in <bool>[true, false]) {
        await expectLater(
          KeyHasValue(path: settings, key: key, value: wanted, holdsWhenEqual: shape).evaluate(
            HostMachine(
              files: FakeFiles(<String, String>{}),
            ).contextFor(const StepName('key_has_value')),
          ),
          throwsA(isA<ConditionUnanswerable>()),
          reason: 'a missing file says nothing about this machine, in either direction',
        );
      }
    });

    test('a file carrying no line for the key at all', () async {
      for (final bool shape in <bool>[true, false]) {
        await expectLater(
          ask('OTHER="subject-public"\n# $key="$wanted"\n', matching: shape),
          throwsA(isA<ConditionUnanswerable>()),
          reason: 'a commented-out assignment is not an assignment',
        );
      }
    });
  });

  group('a path carrying a slot', () {
    test('is filled from the answer the row names', () {
      const KeyHasValue bound = KeyHasValue(
        path: '/etc/subject/settings.<stage>',
        key: key,
        value: wanted,
        holdsWhenEqual: true,
        runAnswer: 'stage',
      );

      expect(
        bound.pathIn(const Arguments(<String, Object>{'stage': 'second'})),
        '/etc/subject/settings.second',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a path with no slot is left exactly as written', () {
      const KeyHasValue plain = KeyHasValue(
        path: settings,
        key: key,
        value: wanted,
        holdsWhenEqual: true,
      );

      expect(plain.pathIn(const Arguments(<String, Object>{'stage': 'prod'})), settings);
    });
  });
}
