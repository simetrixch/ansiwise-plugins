import 'dart:io';

import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:test/test.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// `dart test` discovers whatever is on disk and reports whether any of it failed. Delete a test
/// file and NOTHING fails — the check is not there to fail — and the run goes on to say that every
/// check is green. It is worse than a missing test: a check and its counter-probe live in the same
/// file, so the thing that would have noticed goes with the thing it was watching.
///
/// The reading is [parseChecks] and [disagreements], shared with every other package of this tree
/// through package:ansiwise_checks. What is here is this package's own declaration, the counter-probe
/// that proves the refusal really happens, and where its checks live — all of them directly under
/// `test/`, because this package is nothing but checks.
///
/// `tool/ci.dart` asks one thing this file cannot: whether this file is there at all. It imports no
/// package, so it does not read the declaration; it refuses to start when either half is missing.
void main() {
  group('the declaration this package really carries', () {
    late List<DeclaredCheck> declared;

    setUpAll(() {
      final File file = File('${Directory.current.path}/$checksFileName');
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
          reason: '$check does not name a file of the suite',
        );
      }
    });
  });

  group('counter-probe', () {
    const DeclaredCheck lineEndings = DeclaredCheck(
      name: 'line-endings',
      file: 'test/line_endings_test.dart',
    );

    test('a declared check whose file is gone is reported, by name', () {
      final List<Finding> found = disagreements(
        declared: <DeclaredCheck>[lineEndings],
        checkFilesOnDisk: const <String>[],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, 'test/line_endings_test.dart');
      expect(
        found.single.what,
        contains('line-endings'),
        reason:
            'the name is what a person looks for; a count of missing files says something is wrong '
            'and not what',
      );
    });

    test('a check file nothing declares is reported too', () {
      final List<Finding> found = disagreements(
        declared: const <DeclaredCheck>[],
        checkFilesOnDisk: <String>['test/unagreed_test.dart'],
      );
      expect(found, hasLength(1));
      expect(found.single.subject, 'test/unagreed_test.dart');
    });

    test('a rename is reported from both sides rather than as one silent swap', () {
      expect(
        disagreements(
          declared: <DeclaredCheck>[lineEndings],
          checkFilesOnDisk: <String>['test/line_ending_test.dart'],
        ),
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
          checkFilesOnDisk: <String>['test/line_endings_test.dart'],
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

  group('listing what is on disk', () {
    test('a file that is not a test is not a check of this package', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/test').createSync(recursive: true);
      File('${scratch.path}/test/naming_test.dart').writeAsStringSync('void main() {}\n');
      File('${scratch.path}/test/support.dart').writeAsStringSync('void help() {}\n');
      expect(checkFilesUnder(scratch, 'test'), <String>['test/naming_test.dart']);
    });

    test('a directory of helpers holds no check', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/test/support').createSync(recursive: true);
      File('${scratch.path}/test/support/helper_test.dart').writeAsStringSync('void main() {}\n');
      expect(
        checkFilesUnder(scratch, 'test'),
        isEmpty,
        reason: 'the declaration names the files dart test discovers as checks, not every file',
      );
    });
  });
}

/// Where this package keeps the files that judge it.
const String checksDirectory = 'test';

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-gate-declared-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
