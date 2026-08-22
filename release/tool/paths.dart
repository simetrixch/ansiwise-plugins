/// The path arithmetic this program does for itself.
///
/// `package:path` would answer it, and nothing under `tool/` may import a package: the release notes
/// are written by a job that installs the SDK and runs `dart run tool/release_notes.dart` with no
/// no `package:` import to resolve, so nothing here can make the program unable to start
/// until something had resolved it. So `tool/` imports nothing but `dart:`, and the one thing it
/// needs from a path library is here.
library;

import 'dart:io';

/// The package a program under `tool/` is part of.
///
/// Taken from where the program's own file sits rather than from the working directory, so the
/// program answers the same from anywhere in the tree. [script] is `Platform.script`; it is a
/// parameter rather than read here so that what this resolves to can be asserted.
Directory packageOfToolScript(Uri script) => File.fromUri(script).parent.parent.absolute;

/// The repository [start] sits in: the nearest directory at or above it holding `.git`.
///
/// THE RELEASE IS THE REPOSITORY'S AND NOT THIS PACKAGE'S, which is why this walk exists at all.
/// The twelve plugins a release carries stand beside this package rather than under it, and the
/// workflow that decides which tag starts a release stands above it, so every path this program
/// needs is relative to the repository and not to the package the program lives in.
///
/// A `.git` is a directory in a clone and a FILE in a worktree, and both are found here: a release
/// cut from a worktree is a release like any other.
///
/// Throws [StateError] when there is no `.git` above [start], because then there is no repository
/// here and every answer this program could give would be about something else.
Directory repositoryOf(Directory start) {
  Directory directory = start.absolute;
  while (true) {
    if (Directory('${directory.path}/.git').existsSync() ||
        File('${directory.path}/.git').existsSync()) {
      return directory;
    }
    final Directory parent = directory.parent;
    if (parent.path == directory.path) {
      throw StateError(
        'no .git at or above ${start.path}, so there is no repository here to release and a run '
        'would report about a tree nobody named',
      );
    }
    directory = parent;
  }
}
