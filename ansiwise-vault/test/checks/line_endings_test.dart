import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:test/test.dart';

void main() {
  final LineEndings check = LineEndings(SourceTree.on(repositoryRoot()));

  test('the walk reaches every Dart file of this package', () {
    // A scan that stopped finding files would report a clean tree, which is the one outcome a check
    // must never produce by accident. What says the walk still works is named against the tree
    // rather than against a number: every Dart file that is there has to have been read, so this
    // stays exact whether the package holds five files or five hundred.
    expect(
      check.scannedPaths,
      containsAll(check.tree.dartFiles),
      reason:
          'a Dart file in this tree was not among the ${check.scannedPaths.length} file(s) read, '
          'so this check passed over source it claims to judge',
    );
  });

  test('the manifest is among the files read', () {
    expect(
      check.scannedPaths,
      contains('pubspec.yaml'),
      reason: 'the walk did not reach the root of the package, so it measured a fragment of it',
    );
  });

  test('every file this repository declares as LF is LF in the working copy', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'the gate judges the working copy rather than a fresh checkout, so a file with CRLF '
          'here is a file with CRLF in everything built from it',
    );
  });

  group('counter-probe', () {
    final LineEndings planted = LineEndings(
      SourceTree.planted(<String, String?>{
        'programs/carriage.yaml': 'name: p\r\nroles: [master]\r\n',
        'programs/clean.yaml': 'name: p\nroles: [master]\n',
        'lib/carriage.dart': 'const int x = 1;\r\n',
        // No suffix at all, and the only thing that says it is text is the shebang.
        'ops/sync-versions': '#!/usr/bin/env python3\r\nprint(1)\r\n',
        'ops/clean-versions': '#!/usr/bin/env python3\nprint(1)\n',
        // Neither declared as LF nor opening with a shebang, so it is none of this check's business.
        'notes.txt': 'a line\r\n',
        // Not text: a zero byte is what SourceTree.on answers null for, and a carriage return in an
        // image is a byte of the image.
        'assets/logo.png': null,
      }),
    );
    final List<Finding> reported = planted.findings;

    for (final String path in <String>[
      'programs/carriage.yaml',
      'lib/carriage.dart',
      'ops/sync-versions',
    ]) {
      test('the planted carriage return in $path is reported', () {
        expect(about(reported, path), isNotEmpty, reason: 'this scan cannot go red');
      });
    }

    for (final String path in <String>['programs/clean.yaml', 'ops/clean-versions']) {
      test('$path is LF and is not reported', () {
        expect(
          about(reported, path),
          isEmpty,
          reason: 'this scan reports every file, so a green run would mean nothing',
        );
      });
    }

    test('a file this repository declares nothing about is not read', () {
      expect(planted.scannedPaths, isNot(contains('notes.txt')));
    });

    test('a file that is not text is not read', () {
      expect(
        planted.scannedPaths,
        isNot(contains('assets/logo.png')),
        reason: 'a carriage return inside an image is a byte of the image',
      );
    });
  });
}
