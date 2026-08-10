import 'dart:io';

import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:test/test.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// `dart test` discovers whatever is on disk and reports whether any of it failed. Delete a check
/// file and NOTHING fails — the check is not there to fail — and the run goes on to say that every
/// check is green. It is worse than a missing test: a check and its counter-probe live in the same
/// file, so the thing that would have noticed goes with the thing it was watching.
///
/// The reading is [parseChecks] and [disagreements], shared with every other package of this tree.
/// What is here is this package's own declaration and the counter-probe that proves the refusal
/// really happens.
///
/// WHAT IS DECLARED IS THE CHECKS AND NOT THE WHOLE SUITE. The ordinary tests of this package's
/// steps sit directly under `test/`; what judges the package as a package sits under
/// `test/checks/`, and that is the directory this file holds the declaration against.
///
/// The repository gate asks one thing this file cannot: whether this file is there at all. It reads
/// no declaration — nothing under a gate's tool/ may import a package — and refuses to start when
/// either this file or the declaration beside it is missing.
void main() {
  group('the declaration this package really carries', () {
    late List<DeclaredCheck> declared;

    setUpAll(() {
      final File file = File('${Directory.current.path}/$checksFileName');
      expect(
        file.existsSync(),
        isTrue,
        reason:
            'without it this package cannot say what it checks, and neither can anybody reading it',
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
        disagreements(
          declared: declared,
          checkFilesOnDisk: checkFilesUnder(Directory.current, checksDirectory),
        ),
        isEmpty,
      );
    });

    test('gives every check a name and a file', () {
      for (final DeclaredCheck check in declared) {
        expect(check.name, isNotEmpty, reason: 'a refusal has to be able to name what vanished');
        expect(
          check.file,
          startsWith('$checksDirectory/'),
          reason: '$check does not name a file of the checks of this package',
        );
      }
    });
  });

  group('counter-probe', () {
    // The three shapes, or a green answer here means nothing: a check that vanished must be
    // reported, a check nobody agreed to must be reported, and a declaration that matches must be
    // left alone. Without the third, a reader that reported everything would pass the first two.

    const DeclaredCheck naming = DeclaredCheck(
      name: 'naming',
      file: '$checksDirectory/naming_test.dart',
    );

    test('a declared check whose file is gone is reported, by name', () {
      final List<Finding> found = disagreements(
        declared: <DeclaredCheck>[naming],
        checkFilesOnDisk: const <String>[],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, '$checksDirectory/naming_test.dart');
      expect(
        found.single.what,
        contains('naming'),
        reason:
            'the name is what a person looks for; a count of missing files says something is wrong '
            'and not what',
      );
    });

    test('a check file nothing declares is reported too', () {
      final List<Finding> found = disagreements(
        declared: const <DeclaredCheck>[],
        checkFilesOnDisk: <String>['$checksDirectory/unagreed_test.dart'],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, '$checksDirectory/unagreed_test.dart');
    });

    test('a declaration agreeing with the disk reports nothing', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[naming],
          checkFilesOnDisk: <String>['$checksDirectory/naming_test.dart'],
        ),
        isEmpty,
        reason: 'a reader that reported everything would pass the two probes above',
      );
    });

    test('a rename is reported from both sides rather than as one silent swap', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[naming],
          checkFilesOnDisk: <String>['$checksDirectory/name_test.dart'],
        ),
        hasLength(2),
        reason:
            'one half missing and the other unaccounted for; a single finding would let the reader '
            'think one file simply moved',
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

/// Where this package keeps the files that judge it as a package.
const String checksDirectory = 'test/checks';
