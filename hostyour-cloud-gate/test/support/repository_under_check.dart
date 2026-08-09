/// Which tree is being checked, and how a test gets a scratch tree to plant into.
///
/// The tree is an INPUT now, not a discovery. This package used to live inside the repository it
/// audits and found it by walking upwards until it saw the declaration file; from here that walk
/// climbs out of one repository and into the workspace above it, where it would either find nothing
/// or — worse — find a different checkout and measure that one instead.
///
/// So the tree is named, and the run says which one it measured. A gate that silently checked the
/// wrong tree would report green about a tree nobody asked about, which is the same defect as
/// reporting green about no tree at all.
library;

import 'dart:io';

import 'package:hostyour_cloud_gate/hostyour_cloud_gate.dart';
import 'package:path/path.dart' as p;

/// The file that states what every path of the audited repository is. It is also what identifies
/// the tree: a directory is the tree because it carries its own law, not because of its name.
const String declarationFile = 'branch-classes.yaml';

/// The environment variable that names the tree to check.
const String treeVariable = 'HOSTYOUR_CLOUD_TREE';

/// Where the tree sits when nobody says otherwise: beside the repository this package is in.
///
/// Not a silent fallback — the directory is only accepted when it carries [declarationFile], and a
/// run that finds nothing names both this path and the variable rather than measuring less.
const String conventionalSibling = '../../hostyour-cloud';

/// The repository this package checks.
///
/// Resolution order, and each step is verified rather than assumed:
/// 1. `HOSTYOUR_CLOUD_TREE`, if set. A value that is not a tree is an error, never a fall-through —
///    somebody who named a tree wants THAT tree, and quietly checking a different one is worse
///    than stopping.
/// 2. the sibling checkout, when it carries the declaration file.
Directory repositoryRoot() {
  final String? named = Platform.environment[treeVariable];
  if (named != null && named.trim().isNotEmpty) {
    final Directory directory = Directory(named.trim()).absolute;
    if (!File(p.join(directory.path, declarationFile)).existsSync()) {
      throw StateError(
        '$treeVariable names ${directory.path}, which carries no $declarationFile. That is not a '
        'tree this gate can check, and checking a different one instead would report about a tree '
        'nobody asked for',
      );
    }
    return directory;
  }

  final Directory sibling = Directory(
    p.normalize(p.join(Directory.current.absolute.path, conventionalSibling)),
  );
  if (File(p.join(sibling.path, declarationFile)).existsSync()) {
    return sibling;
  }

  throw StateError(
    'no tree to check: $treeVariable is not set, and $conventionalSibling relative to '
    '${Directory.current.path} carries no $declarationFile. Set $treeVariable to the checkout of '
    'the repository this gate audits',
  );
}

/// Every path git tracks in [root], relative to it and separated by `/`, sorted.
///
/// Read from git and not from the filesystem, because the distinction this repository is built on
/// is between what is TRACKED and what is not: the vendored chart dependencies, the operator's
/// credentials and the compiled binary all sit in the working tree and none of them is product.
///
/// Deliberately WITHOUT `--full-name`, which answers relative to the repository root rather than to
/// [root]. For a whole repository the two agree; for a package inside one they do not, and every
/// path would come back wearing the package directory in front of it — so a tree rooted at the
/// package would hold no path it could match.
List<String> trackedPathsIn(Directory root) {
  final ProcessResult listed = Process.runSync('git', <String>[
    '-C',
    root.path,
    'ls-files',
  ], stdoutEncoding: systemEncoding);
  if (listed.exitCode != 0) {
    throw StateError('git ls-files failed in ${root.path}: ${listed.stderr}');
  }
  final Object? out = listed.stdout;
  final List<String> paths = <String>[
    for (final String line in (out is String ? out : '').split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  paths.sort();
  return paths;
}

/// The repository as an audit sees it: its tracked paths, with their text.
SourceTree repositoryTree() {
  final Directory root = repositoryRoot();
  return SourceTree.readingFrom(root, trackedPathsIn(root));
}

/// This package itself, as an audit sees it.
///
/// One check has its subject HERE and not in the tree under audit: the spelling of Dart directives.
/// The audited repository is charts and manifests and ships no Dart at all, so a directive check
/// pointed at it judges an empty set and can never go red — and the gate survey had already
/// measured that it only ever judged the checker, back when the checker sat inside the tree it
/// checks. Naming this package outright is that fact written down rather than left implied.
SourceTree thisPackageTree() {
  final Directory root = Directory.current.absolute;
  final List<String> tracked = trackedPathsIn(root);
  if (tracked.isEmpty) {
    throw StateError(
      'git tracks nothing under ${root.path}, so there is no package here to judge and a run would '
      'measure nothing',
    );
  }
  return SourceTree.readingFrom(root, tracked);
}
