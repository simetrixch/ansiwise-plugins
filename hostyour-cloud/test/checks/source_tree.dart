/// The tree of files a structural check decides about.
///
/// A check that can only read the repository it lives in cannot be shown to work: it answers
/// "nothing found" when the tree is clean and when the scan is broken, and those are the same
/// output. So every scan under test/checks/ takes a tree rather than reaching for the repository
/// itself. [SourceTree.on] reads what is on disk; [SourceTree.planted] is the scratch tree a
/// counter-probe writes, holding the very thing the check forbids, and it never touches the disk.
///
/// Paths are relative to the root and separated by `/` on every platform, so a planted tree and a
/// read one are described the same way and an assertion reads the same on Windows and on Linux.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Directory names that are never source: build output, editor state, and the dependency
/// directories of other ecosystems. Listed one at a time rather than matched by a pattern, so
/// adding one is a decision somebody makes here.
const Set<String> prunedDirectories = <String>{
  '.git',
  '.dart_tool',
  'build',
  'node_modules',
  'Pods',
};

/// The lines of [text], without their terminators.
List<String> linesOf(String text) => const LineSplitter().convert(text);

/// The repository this test suite is part of.
///
/// `dart test` runs with the package directory as the working directory, and the package is the
/// repository root here. The walk upwards is what makes a run from a subdirectory answer the same
/// thing instead of quietly scanning less.
Directory repositoryRoot() {
  Directory directory = Directory.current.absolute;
  while (true) {
    if (File(p.join(directory.path, 'pubspec.yaml')).existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'no pubspec.yaml at or above ${Directory.current.path}, so there is no repository to '
        'scan and a check running here would measure nothing',
      );
    }
    directory = parent;
  }
}

/// A tree of files, and the Dart packages in it.
final class SourceTree {
  SourceTree._({required this.rootName, required this.files, required this.directories})
    : packages = _packagesIn(files);

  /// The tree a counter-probe writes: every path is a key of [files], and the directories are the
  /// prefixes of those paths.
  ///
  /// A path mapped to null is a file that is not text — what [SourceTree.on] answers for a binary.
  /// Planting one is how a check that reads content is shown to step past what it cannot read.
  factory SourceTree.planted(Map<String, String?> files, {String rootName = 'planted'}) {
    final Set<String> directories = <String>{};
    for (final String path in files.keys) {
      final List<String> segments = path.split('/');
      for (int i = 1; i < segments.length; i++) {
        directories.add(segments.take(i).join('/'));
      }
    }
    return SourceTree._(
      rootName: rootName,
      files: Map<String, String?>.of(files),
      directories: directories,
    );
  }

  /// The tree on disk under [root].
  factory SourceTree.on(Directory root) {
    final Map<String, String?> files = <String, String?>{};
    final Set<String> directories = <String>{};
    _walk(root, '', files, directories);
    return SourceTree._(rootName: p.basename(root.path), files: files, directories: directories);
  }

  /// What the root directory is called, for a rule that names one.
  final String rootName;

  /// Every file in the tree, against its text — or against null when it is not text.
  ///
  /// A byte scan over an image reports matches nobody can act on, so a file holding a zero byte is
  /// counted as present and left unread. A check over names still sees it; a check over content
  /// steps past it.
  final Map<String, String?> files;

  /// Every directory in the tree.
  final Set<String> directories;

  /// The Dart packages in this tree: the directory each sits in, against the name its manifest
  /// declares. The root directory is the empty string.
  ///
  /// The name is read from the manifest rather than derived from the directory, because the two
  /// differ by design — the directory is `hostyour-cloud` and the package is `hostyour_cloud`, since a
  /// Dart package name may not carry a hyphen.
  final Map<String, String> packages;

  /// Every Dart source file in the tree, sorted.
  List<String> get dartFiles =>
      files.keys.where((String path) => path.endsWith('.dart')).toList(growable: false)..sort();

  /// The text of [path], or null when it is not there or is not text.
  String? textOf(String path) => files[path];

  /// The paths in [directory] and under it, files and directories alike, sorted. The empty string
  /// means the whole tree, and the directory itself is included.
  List<String> namesUnder(String directory) {
    final List<String> under = <String>[
      ...files.keys,
      ...directories,
    ].where((String path) => _isUnder(path, directory)).toList(growable: false);
    under.sort();
    return <String>[if (directory.isNotEmpty) directory, ...under];
  }

  /// Whether [path] is [directory] itself or sits under it. The empty directory is the whole tree.
  static bool _isUnder(String path, String directory) =>
      directory.isEmpty || path == directory || path.startsWith('$directory/');

  /// The directory part of [path], or the empty string when it sits at the root.
  static String directoryOf(String path) {
    final int cut = path.lastIndexOf('/');
    return cut < 0 ? '' : path.substring(0, cut);
  }

  static void _walk(
    Directory directory,
    String prefix,
    Map<String, String?> files,
    Set<String> directories,
  ) {
    final List<FileSystemEntity> entries = directory.listSync(followLinks: false)
      ..sort((FileSystemEntity a, FileSystemEntity b) => a.path.compareTo(b.path));
    for (final FileSystemEntity entry in entries) {
      final String name = p.basename(entry.path);
      if (prunedDirectories.contains(name)) {
        continue;
      }
      final String path = prefix.isEmpty ? name : '$prefix/$name';
      if (entry is Directory) {
        directories.add(path);
        _walk(entry, path, files, directories);
      } else if (entry is File) {
        files[path] = _textOf(entry);
      }
    }
  }

  static String? _textOf(File file) {
    final List<int> bytes = file.readAsBytesSync();
    if (bytes.contains(0)) {
      return null;
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Map<String, String> _packagesIn(Map<String, String?> files) {
    final bool rootHoldsCode = files.keys.any(
      (String path) => path.startsWith('lib/') || path.startsWith('bin/'),
    );
    final Map<String, String> packages = <String, String>{};
    for (final MapEntry<String, String?> entry in files.entries) {
      if (p.posix.basename(entry.key) != 'pubspec.yaml') {
        continue;
      }
      final String directory = directoryOf(entry.key);
      // A manifest at the root of a tree that carries no lib/ and no bin/ of its own declares a
      // workspace rather than a package, and walking it would count every member twice.
      if (directory.isEmpty && !rootHoldsCode) {
        continue;
      }
      final String? name = _declaredName(entry.value);
      if (name == null) {
        continue;
      }
      packages[directory] = name;
    }
    return packages;
  }

  static String? _declaredName(String? manifest) {
    if (manifest == null) {
      return null;
    }
    for (final String line in linesOf(manifest)) {
      final RegExpMatch? match = _nameLine.firstMatch(line);
      if (match != null) {
        return match.group(1);
      }
    }
    return null;
  }

  static final RegExp _nameLine = RegExp(r'^name:\s*(\S+)');
}
