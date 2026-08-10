import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:test/test.dart';

/// case-sensitivity — every import spells the on-disk file name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step in this plugin runs against and the machine the binary is compiled for.
/// Nothing else catches it: the analyzer resolves the import through the filesystem, and the Windows
/// filesystem opens the wrong case without complaint. For the same reason a check that asked whether
/// the file opens would be green here and prove nothing.
///
/// THE TREE IS THIS PACKAGE'S OWN, AND EVERY OTHER PACKAGE RUNS THE SAME AUDIT OVER ITS OWN. The
/// four tool packages this plugin stands on are a DEPENDENCY here, resolved from a pin or a checkout
/// beside this one, so not one of their files is a path of this tree — a scan rooted here would step
/// past every step they ship and report a clean answer over code it never opened.
void main() {
  final DirectiveCase check = DirectiveCase(SourceTree.on(repositoryRoot()));

  test('there are imports of this tree to judge', () {
    expect(
      check.directivesJudged,
      isNotEmpty,
      reason: 'no directive names a file of this tree, so this check measured nothing',
    );
  });

  test('every import spells the on-disk name byte for byte', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'each finding reads <file>:<line> — <uri> — on disk it is <path>; the fix is to spell '
          'the import exactly as the listing does, because on Linux the wrong case does not open',
    );
  });

  group('counter-probe', () {
    // A check that cannot go red proves nothing, so the same scan runs over planted trees carrying
    // the mismatch it must report and the exact spelling it must leave alone.

    test('an import whose case differs from the on-disk name is reported', () {
      final List<Finding> reported = _reportedIn(<String, String>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'src/steps/cluster/Apply_thing.dart';",
      });
      expect(reported, hasLength(1), reason: 'this scan cannot go red on the defect it exists for');
      expect(
        reported.single.what,
        contains('lib/src/steps/cluster/apply_thing.dart'),
        reason: 'a finding that does not name the on-disk spelling leaves the fix to a guess',
      );
    });

    test('an import that matches byte for byte is not reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
          'lib/right.dart': "import 'src/steps/cluster/apply_thing.dart';",
        }),
        isEmpty,
        reason: 'this scan refuses correct code',
      );
    });

    test('a directory segment with the wrong case is reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
          'lib/wrong.dart': "import 'src/steps/Cluster/apply_thing.dart';",
        }),
        hasLength(1),
        reason:
            'the whole resolved path is compared, not the file name alone; a directory opened '
            'under the wrong case fails on Linux exactly like a file',
      );
    });

    test('a relative path that climbs is resolved before it is compared', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/gitops/stage_config.dart': 'const int x = 1;',
          'lib/src/steps/cluster/wrong.dart': "import '../gitops/Stage_config.dart';",
        }),
        hasLength(1),
      );
    });

    test('a package: import of a package of this tree is judged like a relative one', () {
      final List<Finding> reported = _reportedIn(<String, String>{
        'pubspec.yaml': 'name: planted\n',
        'lib/src/registry.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'package:planted/src/Registry.dart';",
        'lib/right.dart': "import 'package:planted/src/registry.dart';",
      });
      expect(reported, hasLength(1));
      expect(reported.single.subject, 'lib/wrong.dart');
    });

    test('an export and a part are judged like an import', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
          'lib/exports.dart': "export 'src/steps/cluster/Apply_thing.dart';",
          'lib/parent.dart': "part 'src/steps/cluster/Apply_thing.dart';",
        }),
        hasLength(2),
        reason: 'an export and a part resolve a file exactly as an import does',
      );
    });

    test('a part of naming its parent with the wrong case is reported', () {
      expect(
        _reportedIn(<String, String>{
          'lib/parent.dart': "part 'child.dart';",
          'lib/child.dart': "part of 'Parent.dart';",
        }),
        hasLength(1),
        reason: 'the child names its parent on its own, so the parent directive does not cover it',
      );
    });

    test('a finding names the line the directive sits on', () {
      expect(
        _reportedIn(<String, String>{
          'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
          'lib/wrong.dart': "// a first line\nimport 'src/steps/cluster/Apply_thing.dart';",
        }).single.line,
        2,
        reason: 'a finding without a line names a file of unknown length',
      );
    });

    test('an import of a file that is on disk under no spelling is not a finding here', () {
      expect(
        _reportedIn(<String, String>{'lib/broken.dart': "import 'src/steps/not_there.dart';"}),
        isEmpty,
        reason: 'that import is broken on every platform, and the analyzer reports it',
      );
    });

    test('dart: and third-party package: imports are not judged', () {
      final DirectiveCase planted = DirectiveCase(
        SourceTree.planted(<String, String>{
          'lib/uses_others.dart':
              "import 'dart:io';\n"
              "import 'package:ansiwise_api/ansiwise_api.dart';",
        }),
      );
      expect(planted.directivesJudged, isEmpty);
      expect(planted.findings, isEmpty);
    });

    test('a file that is not text carries no directive to resolve', () {
      expect(
        DirectiveCase(
          SourceTree.planted(<String, String?>{
            'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
            'assets/logo.png': null,
          }),
        ).findings,
        isEmpty,
      );
    });
  });
}

List<Finding> _reportedIn(Map<String, String> files) =>
    DirectiveCase(SourceTree.planted(files)).findings;
