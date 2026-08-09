import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'source_tree.dart';

/// case-sensitivity — every import spells the on-disk file name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step in this plugin runs against and the machine the binary is compiled for.
/// Nothing else catches it: the analyzer resolves the import through the filesystem, and the Windows
/// filesystem opens the wrong case without complaint. For the same reason a check that asked whether
/// the file opens would be green here and prove nothing. The comparison is against the DIRECTORY
/// LISTING instead: [SourceTree.on] walks the tree by listing it, so its paths carry each name as the
/// disk spells it, and every directive's resolved path is compared to them byte for byte.
///
/// What is judged is every `import`, `export`, `part` and `part of` directive whose target is a
/// file of this tree — relative, or `package:` of a package this tree holds. `dart:` names no file,
/// and a third-party package resolves through the pub cache, whose spelling is pub's and not this
/// repository's. `package:ansiwise_api/…` is one of those: the framework is a dependency here,
/// resolved from a git ref or from a checkout beside this one, and neither is a path of this tree.
///
/// A directive whose target is on disk under NO spelling is not a finding here: that import is
/// broken on every platform, and the analyzer reports it.
void main() {
  final SourceTree tree = SourceTree.on(repositoryRoot());

  test('there are imports of this tree to judge', () {
    expect(
      inTreeImportsIn(tree),
      isNotEmpty,
      reason: 'no directive names a file of this tree, so this check measured nothing',
    );
  });

  test('every import spells the on-disk name byte for byte', () {
    expect(
      caseMismatchesIn(tree),
      isEmpty,
      reason:
          'each finding reads <file>:<line>: <uri> — on disk it is <path>; the fix is to spell '
          'the import exactly as the listing does, because on Linux the wrong case does not open',
    );
  });

  group('counter-probe', () {
    // A check that cannot go red proves nothing, so the same scan runs over planted trees carrying
    // the mismatch it must report and the exact spelling it must leave alone.

    test('an import whose case differs from the on-disk name is reported', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'src/steps/cluster/Apply_thing.dart';",
      });
      final List<String> reported = caseMismatchesIn(planted);
      expect(reported, hasLength(1), reason: 'this scan cannot go red on the defect it exists for');
      expect(
        reported.single,
        contains('lib/src/steps/cluster/apply_thing.dart'),
        reason: 'a finding that does not name the on-disk spelling leaves the fix to a guess',
      );
    });

    test('an import that matches byte for byte is not reported', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'lib/right.dart': "import 'src/steps/cluster/apply_thing.dart';",
      });
      expect(caseMismatchesIn(planted), isEmpty, reason: 'this scan refuses correct code');
    });

    test('a directory segment with the wrong case is reported', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'src/steps/Cluster/apply_thing.dart';",
      });
      expect(
        caseMismatchesIn(planted),
        hasLength(1),
        reason:
            'the whole resolved path is compared, not the file name alone; a directory opened '
            'under the wrong case fails on Linux exactly like a file',
      );
    });

    test('a relative path that climbs is resolved before it is compared', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/gitops/vault_api.dart': 'const int x = 1;',
        'lib/src/steps/cluster/wrong.dart': "import '../gitops/Vault_api.dart';",
      });
      expect(caseMismatchesIn(planted), hasLength(1));
    });

    test('a package: import of a package of this tree is judged like a relative one', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'pubspec.yaml': 'name: planted\n',
        'lib/src/steps/gitops/vault_api.dart': 'const int x = 1;',
        'lib/wrong.dart': "import 'package:planted/src/steps/gitops/Vault_api.dart';",
        'lib/right.dart': "import 'package:planted/src/steps/gitops/vault_api.dart';",
      });
      final List<String> reported = caseMismatchesIn(planted);
      expect(reported, hasLength(1));
      expect(reported.single, startsWith('lib/wrong.dart:'));
    });

    test('an export and a part are judged like an import', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'lib/exports.dart': "export 'src/steps/cluster/Apply_thing.dart';",
        'lib/parent.dart': "part 'src/steps/cluster/Apply_thing.dart';",
      });
      expect(
        caseMismatchesIn(planted),
        hasLength(2),
        reason: 'an export and a part resolve a file exactly as an import does',
      );
    });

    test('a part of naming its parent with the wrong case is reported', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/parent.dart': "part 'child.dart';",
        'lib/child.dart': "part of 'Parent.dart';",
      });
      expect(
        caseMismatchesIn(planted),
        hasLength(1),
        reason: 'the child names its parent on its own, so the parent directive does not cover it',
      );
    });

    test('an import of a file that is on disk under no spelling is not a finding here', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/broken.dart': "import 'src/steps/not_there.dart';",
      });
      expect(
        caseMismatchesIn(planted),
        isEmpty,
        reason: 'that import is broken on every platform, and the analyzer reports it',
      );
    });

    test('dart: and third-party package: imports are not judged', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/uses_others.dart':
            "import 'dart:io';\n"
            "import 'package:ansiwise_api/ansiwise_api.dart';",
      });
      expect(inTreeImportsIn(planted), isEmpty);
      expect(caseMismatchesIn(planted), isEmpty);
    });

    test('a file that is not text carries no directive to resolve', () {
      final SourceTree planted = SourceTree.planted(<String, String?>{
        'lib/src/steps/cluster/apply_thing.dart': 'const int x = 1;',
        'assets/logo.png': null,
      });
      expect(caseMismatchesIn(planted), isEmpty);
    });
  });
}

/// Every `import`, `export`, `part` and `part of` directive of [tree] that names a file of this
/// tree under some spelling, as `<file>: <uri>`.
///
/// This is the denominator of the check: a run in which it is empty judged nothing, and its
/// silence must not read as agreement.
List<String> inTreeImportsIn(SourceTree tree) {
  final Map<String, String> listing = _byLowerCase(tree);
  return <String>[
    for (final _Directive directive in _directivesOf(tree))
      if (listing.containsKey(directive.target.toLowerCase()))
        '${directive.file}: ${directive.uri}',
  ];
}

/// Every directive of [tree] whose spelling differs from the on-disk name, as
/// `<file>:<line>: <uri> — on disk it is <path>`.
List<String> caseMismatchesIn(SourceTree tree) {
  final Map<String, String> listing = _byLowerCase(tree);
  final List<String> found = <String>[];
  for (final _Directive directive in _directivesOf(tree)) {
    if (tree.files.containsKey(directive.target)) {
      continue;
    }
    final String? actual = listing[directive.target.toLowerCase()];
    if (actual == null) {
      continue;
    }
    found.add('${directive.file}:${directive.line}: ${directive.uri} — on disk it is $actual');
  }
  return found;
}

/// The files of [tree], keyed by their lower-cased path.
///
/// Lower-casing both sides is what makes "same file, different spelling" one lookup; the value
/// keeps the spelling the listing carries, which is what a finding names as the fix.
Map<String, String> _byLowerCase(SourceTree tree) => <String, String>{
  for (final String path in tree.files.keys) path.toLowerCase(): path,
};

/// One directive, resolved to the tree-relative path it names.
final class _Directive {
  const _Directive({
    required this.file,
    required this.line,
    required this.uri,
    required this.target,
  });

  final String file;
  final int line;
  final String uri;
  final String target;
}

/// Every directive of every Dart file of [tree] whose URI can name a file of this tree.
Iterable<_Directive> _directivesOf(SourceTree tree) sync* {
  for (final String file in tree.dartFiles) {
    final String? text = tree.textOf(file);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      final String? uri = _directiveLine.firstMatch(lines[i])?.group(2);
      if (uri == null) {
        continue;
      }
      final String? target = _targetOf(tree, file, uri);
      if (target != null) {
        yield _Directive(file: file, line: i + 1, uri: uri, target: target);
      }
    }
  }
}

/// The tree-relative path [uri] names from [file], or null when it names no file of this tree.
String? _targetOf(SourceTree tree, String file, String uri) {
  if (uri.startsWith('dart:')) {
    return null;
  }
  if (uri.startsWith('package:')) {
    final String rest = uri.substring('package:'.length);
    final int slash = rest.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final String? directory = _directoryOfPackage(tree, rest.substring(0, slash));
    if (directory == null) {
      // A package name this tree does not declare resolves through the pub cache, whose spelling
      // is pub's and not this repository's.
      return null;
    }
    return p.posix.normalize(p.posix.join(directory, 'lib', rest.substring(slash + 1)));
  }
  return p.posix.normalize(p.posix.join(SourceTree.directoryOf(file), uri));
}

String? _directoryOfPackage(SourceTree tree, String name) {
  for (final MapEntry<String, String> package in tree.packages.entries) {
    if (package.value == name) {
      return package.key;
    }
  }
  return null;
}

/// The one URI-carrying shape of each directive kind, matched at the start of a line.
///
/// `part of` is tried before bare `part`, so the URI taken is the one behind the whole marker.
/// The line anchor is also what keeps this file from reporting itself: a directive planted as a
/// string literal in a counter-probe sits behind a quote, never at the start of a line.
final RegExp _directiveLine = RegExp(
  r'''^\s*(?:import|export|part\s+of|part)\s+(['"])([^'"]+)\1''',
);
