/// What this gate says it checks, read from `checks.yaml`.
///
/// A gate that discovers its checks by listing the disk cannot tell "there is no such check" from
/// "the check passed". `dart test` does exactly that: delete a file and nothing fails, because the
/// check is not there to fail — and the run reports that every check is green. A check and its
/// counter-probe live in the same file, so the thing that would have noticed goes with the thing it
/// was watching.
///
/// So the gate is TOLD what it checks, and holds the disk against that.
///
/// IT PARSES BY LINE AND IMPORTS NOTHING BUT dart:io. Everything under `tool/` has to be able to run
/// on a fresh clone where no package has been resolved — `dart pub get` is the gate's own first step
/// — so a YAML parser from a package is not available here. The format is one entry per line, which
/// is all this needs and all `checks.yaml` uses.
library;

import 'dart:io';

/// A check the gate declares, and where it lives.
final class DeclaredCheck {
  /// The check called [name], carried by the file at [file].
  const DeclaredCheck({required this.name, required this.file});

  /// What the check is called, which is what a refusal names.
  final String name;

  /// Where it lives, relative to the package root, with `/` separators.
  final String file;

  @override
  String toString() => '$name ($file)';
}

/// Every check declared in [text], in the order it declares them.
///
/// A parameter rather than a path, so a probe can drive the same parsing over a declaration it wrote
/// itself. Blank lines and comment lines are not entries; anything else must be `<name>: <file>`.
List<DeclaredCheck> parseChecks(String text) {
  final List<DeclaredCheck> declared = <DeclaredCheck>[];
  for (final String raw in text.split('\n')) {
    final String line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int colon = line.indexOf(':');
    if (colon < 1) {
      continue;
    }
    declared.add(
      DeclaredCheck(name: line.substring(0, colon).trim(), file: line.substring(colon + 1).trim()),
    );
  }
  return declared;
}

/// Why the declaration and the disk disagree, or an empty list when they do not.
///
/// BOTH DIRECTIONS, and the second is the one that is easy to leave out. A declared check that is
/// not on disk is the defect this exists for. An undeclared test file is the other half: a check
/// nobody agreed to is how a suite grows a file that judges nothing, and it is also what a rename
/// looks like from here — the old name missing and a new one unaccounted for, rather than one
/// silent replacement.
List<String> disagreements({
  required List<DeclaredCheck> declared,
  required List<String> testFilesOnDisk,
}) {
  final Set<String> onDisk = testFilesOnDisk.toSet();
  final Set<String> named = <String>{for (final DeclaredCheck check in declared) check.file};
  return <String>[
    for (final DeclaredCheck check in declared)
      if (!onDisk.contains(check.file))
        'the check "${check.name}" is declared at ${check.file} and that file is not there — the '
            'check and its counter-probe are gone together, and nothing else would have said so',
    for (final String file in testFilesOnDisk)
      if (!named.contains(file))
        '$file is a test file that checks.yaml does not declare — a check nobody agreed to, or a '
            'rename whose other half was left behind',
  ];
}

/// Every `*_test.dart` directly under `test/` of [package], with `/` separators, sorted.
List<String> testFilesUnder(Directory package) {
  final Directory tests = Directory('${package.path}/test');
  if (!tests.existsSync()) {
    return const <String>[];
  }
  final List<String> found = <String>[
    for (final FileSystemEntity entry in tests.listSync(followLinks: false))
      if (entry is File && entry.path.endsWith('_test.dart'))
        'test/${entry.path.split(RegExp(r'[/\\]')).last}',
  ];
  found.sort();
  return found;
}
