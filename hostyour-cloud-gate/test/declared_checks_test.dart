import 'dart:io';

import 'package:test/test.dart';

import '../tool/declared_checks.dart';

/// The gate is told what it checks, and holds the disk against it.
///
/// `dart test` discovers whatever is on disk and reports whether any of it failed. Delete a test
/// file and NOTHING fails — the check is not there to fail — and the run goes on to say that every
/// check is green. It is worse than a missing test: a check and its counter-probe live in the same
/// file, so the thing that would have noticed goes with the thing it was watching.
///
/// `tool/ci.dart` therefore reads `checks.yaml` before anything runs and stops when the two
/// disagree. This file drives the same reading over declarations written for the purpose, so the
/// refusal is proven to happen rather than assumed — which is the whole point of the mechanism and
/// would be the first thing to go quiet if it were only asserted in prose.
void main() {
  group('the declaration this repository really carries', () {
    late List<DeclaredCheck> declared;

    setUpAll(() {
      final File file = File('${Directory.current.path}/checks.yaml');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'without it this gate cannot say what it checks, and neither can anybody reading it',
      );
      declared = parseChecks(file.readAsStringSync());
    });

    test('names at least one check', () {
      expect(
        declared,
        isNotEmpty,
        reason: 'an empty declaration agrees with an empty suite, and both are green for nothing',
      );
    });

    test('agrees with the files on disk, in both directions', () {
      expect(
        disagreements(declared: declared, testFilesOnDisk: testFilesUnder(Directory.current)),
        isEmpty,
      );
    });

    test('gives every check a name and a file', () {
      for (final DeclaredCheck check in declared) {
        expect(check.name, isNotEmpty, reason: 'a refusal has to be able to name what vanished');
        expect(check.file, startsWith('test/'), reason: '$check does not name a file of the suite');
      }
    });
  });

  group('counter-probe', () {
    const DeclaredCheck lineEndings = DeclaredCheck(
      name: 'line-endings',
      file: 'test/line_endings_test.dart',
    );

    test('a declared check whose file is gone is reported, by name', () {
      final List<String> found = disagreements(
        declared: <DeclaredCheck>[lineEndings],
        testFilesOnDisk: const <String>[],
      );
      expect(found, hasLength(1));
      expect(
        found.single,
        allOf(contains('line-endings'), contains('test/line_endings_test.dart')),
        reason:
            'the name is what a person looks for; a count of missing files says something is wrong '
            'and not what',
      );
    });

    test('a test file nothing declares is reported too', () {
      final List<String> found = disagreements(
        declared: const <DeclaredCheck>[],
        testFilesOnDisk: <String>['test/unagreed_test.dart'],
      );
      expect(found, hasLength(1));
      expect(found.single, contains('test/unagreed_test.dart'));
    });

    test('a rename is reported from both sides rather than as one silent swap', () {
      final List<String> found = disagreements(
        declared: <DeclaredCheck>[lineEndings],
        testFilesOnDisk: <String>['test/line_ending_test.dart'],
      );
      expect(
        found,
        hasLength(2),
        reason:
            'one half missing and the other unaccounted for; a single finding would let the reader '
            'think one file simply moved',
      );
    });

    test('a declaration agreeing with the disk reports nothing', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[lineEndings],
          testFilesOnDisk: <String>['test/line_endings_test.dart'],
        ),
        isEmpty,
      );
    });
  });

  group('reading the declaration', () {
    test('comments and blank lines are not checks', () {
      expect(
        parseChecks('# a comment\n\n  # an indented comment\nnaming: test/naming_test.dart\n'),
        hasLength(1),
      );
    });

    test('the name and the file come off either side of the colon, trimmed', () {
      final DeclaredCheck check = parseChecks('  naming :  test/naming_test.dart  \n').single;
      expect(check.name, 'naming');
      expect(check.file, 'test/naming_test.dart');
    });

    test('a line with no colon is not half a check', () {
      expect(
        parseChecks('naming\n'),
        isEmpty,
        reason: 'a check with no file to point at would be declared and unfindable at once',
      );
    });
  });
}
