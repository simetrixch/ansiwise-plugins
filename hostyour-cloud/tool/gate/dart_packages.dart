/// Finding the Dart packages of a tree.
///
/// Discovery is a search of the tree, not a read of a workspace list. A package that is on disk but
/// not listed is exactly the case the gate must still see: it compiles, imports and breaks a rule
/// like any other, and reading the list would let it do so unwatched.
library;

import 'dart:io';

import 'paths.dart';

/// A Dart package on disk.
final class DartPackage {
  /// Records the package rooted at [directory], declaring itself [name].
  const DartPackage({required this.directory, required this.name});

  /// Where it sits, as this operating system names it.
  final String directory;

  /// What its manifest declares, which is what an import says after `package:`.
  ///
  /// Read from the manifest rather than derived from the directory, because the two differ by
  /// design: the directory is `hostyour-cloud` and the package is `hostyour_cloud`, since a Dart package
  /// name may not carry a hyphen.
  final String name;

  @override
  String toString() => '$name at $directory';
}

/// Directory names that are never source: build output, editor state, and the dependency directories
/// of other ecosystems.
const Set<String> prunedDirectories = <String>{
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  'Pods',
};

/// Every Dart package under [root], sorted by directory.
///
/// The root itself counts when it carries code — anything else would make a one-package repository
/// invisible to the gate. A manifest at the root of a tree with no `lib/` and no `bin/` of its own
/// declares a workspace rather than a package, and walking it would count every member twice.
List<DartPackage> dartPackagesIn(Directory root) {
  final List<DartPackage> found = <DartPackage>[];
  final bool rootHoldsCode =
      Directory('${root.path}/lib').existsSync() || Directory('${root.path}/bin').existsSync();

  void walk(Directory directory) {
    final File manifest = File('${directory.path}/pubspec.yaml');
    final bool isRoot = directory.path == root.path;
    if (manifest.existsSync() && (!isRoot || rootHoldsCode)) {
      final String? name = declaredPackageName(manifest.readAsStringSync());
      if (name != null) {
        found.add(DartPackage(directory: directory.path, name: name));
      }
    }
    for (final FileSystemEntity entry in directory.listSync(followLinks: false)) {
      if (entry is Directory && !prunedDirectories.contains(baseName(entry.path))) {
        walk(entry);
      }
    }
  }

  walk(root);
  found.sort((DartPackage a, DartPackage b) => a.directory.compareTo(b.directory));
  return found;
}

/// The name [manifest] declares, or null when it declares none.
String? declaredPackageName(String manifest) {
  for (final String line in manifest.split('\n')) {
    final RegExpMatch? match = _nameLine.firstMatch(line.trimRight());
    if (match != null) {
      return match.group(1);
    }
  }
  return null;
}

final RegExp _nameLine = RegExp(r'^name:\s*(\S+)');
