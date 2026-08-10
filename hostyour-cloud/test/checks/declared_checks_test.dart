import 'dart:io';

import 'package:ansiwise_checks/audits.dart';
import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/declared_checks.dart';
import '../../tool/gate/paths.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// The reading and its counter-probe are [auditDeclaredChecks], shared with every other package of
/// this tree. What is here besides it is THE OTHER HALF, and this repository is where it is driven:
/// the reading cannot notice its own absence — a check and its counter-probe live in one file, so
/// deleting the reader takes the reading with it and leaves `checks.yaml` describing a suite nobody
/// compares anything to. So `tool/gate/declared_checks.dart` asks, for every package of the
/// repository, whether the two files are there, and it is driven below over planted packages,
/// because a refusal nobody has seen go red is a refusal nobody has.
void main() {
  auditDeclaredChecks();

  group('what the repository gate asks before anything runs', () {
    test('every package of this repository that has a suite carries both files', () {
      expect(
        undeclaredSuites(dartPackagesIn(repositoryOf(Directory.current))),
        isEmpty,
        reason:
            'this is the gate refusing to start, run here so the tree says whether it would — a '
            'package whose declaration or whose reader is gone is a package nothing holds to what '
            'it says it checks',
      );
    });

    test('a package with a suite and no declaration is reported, by name', () {
      final DartPackage planted = _plantedPackage(
        checks: <String>['test/checks/naming_test.dart', 'test/checks/declared_checks_test.dart'],
      );
      final List<String> refusals = undeclaredSuites(<DartPackage>[planted]);
      expect(refusals, hasLength(1), reason: 'this refusal cannot go red on what it exists for');
      expect(refusals.single, allOf(contains(planted.name), contains(checksFile)));
    });

    test('a package whose reader is gone is reported, even with the declaration still there', () {
      // The shape the suite itself cannot see: checks.yaml still names every check, and the file
      // that would have held it against the disk went with its own counter-probe.
      final DartPackage planted = _plantedPackage(
        declaration: true,
        checks: <String>['test/checks/naming_test.dart'],
      );
      final List<String> refusals = undeclaredSuites(<DartPackage>[planted]);
      expect(refusals, hasLength(1));
      expect(refusals.single, contains(declaredChecksGuard));
    });

    test('a package carrying both is not reported', () {
      expect(
        undeclaredSuites(<DartPackage>[
          _plantedPackage(
            declaration: true,
            checks: <String>[
              'test/checks/naming_test.dart',
              'test/checks/declared_checks_test.dart',
            ],
          ),
        ]),
        isEmpty,
        reason: 'a refusal that reported everything would pass the two probes above',
      );
    });

    test('a package that keeps its checks directly under test/ is judged there', () {
      // A package that is nothing but checks has no test/checks/ at all, and its reader sits one
      // directory up. A rule that only ever looked in test/checks/ would report it as missing on
      // every run and be switched off.
      expect(
        undeclaredSuites(<DartPackage>[
          _plantedPackage(declaration: true, checks: <String>['test/declared_checks_test.dart']),
        ]),
        isEmpty,
      );
    });

    test('a package with no suite at all is not judged', () {
      expect(
        undeclaredSuites(<DartPackage>[_plantedPackage()]),
        isEmpty,
        reason:
            'there is nothing for a declaration to be held against, and the gate already says out '
            'loud that such a package was not tested',
      );
    });
  });
}

/// A package on disk carrying [checks] and, where [declaration] says so, the file that declares them.
DartPackage _plantedPackage({bool declaration = false, List<String> checks = const <String>[]}) {
  final Directory scratch = Directory.systemTemp.createTempSync('hostyour-cloud-declared-');
  addTearDown(() => scratch.deleteSync(recursive: true));
  if (declaration) {
    File('${scratch.path}/$checksFile').writeAsStringSync('naming: test/checks/naming_test.dart\n');
  }
  for (final String path in checks) {
    final File file = File('${scratch.path}/$path');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('void main() {}\n');
  }
  return DartPackage(directory: scratch.path, name: 'planted_package');
}
