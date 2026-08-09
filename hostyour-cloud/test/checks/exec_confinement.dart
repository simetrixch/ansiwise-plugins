/// exec-confinement — nothing in a shipped library outside `infrastructure/` reaches the machine.
///
/// The dry-run guarantee is that `--mode dry` cannot change anything, and it rests on two
/// independent things: the engine calls a step's plan and never its apply, and the ports handed to
/// the step — `Shell`, `Files`, `Http` — throw on any call the step did not declare as only looking.
/// The second is what holds when the first is wrong.
///
/// It holds only for what goes THROUGH those ports. A step that writes `Process.run(...)` or
/// `File(path).writeAsString(...)` has left the framework: the port never sees the call, the run
/// record never mentions it, and the dry run reports that nothing would change while the machine was
/// already changed. Nothing about that line looks wrong in review — it is shorter than the port call
/// and does the same thing on a real run.
///
/// So the reach itself is confined by name. A directory called `infrastructure/` is where a port is
/// implemented against the real machine; everywhere else in the shipped library asks a port.
library;

import 'finding.dart';
import 'source_tree.dart';

/// The five ways out of the process.
///
/// Matched case-SENSITIVELY and word-anchored, because these are Dart identifiers: the prose "a step
/// never starts a process itself" is not a reference to `Process`, and the port class `Files` is not
/// `File`.
const List<String> waysOut = <String>['dart:io', 'Process', 'File', 'HttpClient', 'SSHClient'];

/// The directories of a package that are not its shipped library, matched at the package root.
///
/// `test/` — a test that could not open `programs/deploy-host.yaml` would be verifying a copy of the
/// program pasted into it rather than the program that ships.
///
/// `bin/` — the entry point reads the process's own arguments and sets its exit code, which is one
/// library and can be nothing else.
///
/// `tool/` — the gate's own programs. They drive the Dart toolchain on a developer machine and are
/// never carried onto a deployed one, so no dry run of a deployment passes through them.
///
/// `lib/src/testing/` is deliberately NOT among them: it ships, it is the fake machine the framework
/// hands to a step's test, and a fake that reached the real one would defeat the thing it exists for.
const List<String> notTheShippedLibrary = <String>['test', 'bin', 'tool'];

/// The scan itself, over a tree it is given rather than over the repository it lives in.
final class ExecConfinement {
  /// Judges [tree].
  const ExecConfinement(this.tree);

  /// The tree being judged.
  final SourceTree tree;

  /// The Dart files the rule applies to, sorted.
  ///
  /// Empty means the scan decided about nothing, which is the one outcome that reads like a pass and
  /// is not one.
  List<String> get confinedFiles =>
      tree.dartFiles.where((String path) => !_reachIsAllowedIn(path)).toList(growable: false);

  /// Every reference to a way out from a file the rule applies to.
  List<Finding> get findings {
    final List<Finding> found = <Finding>[];
    for (final String path in confinedFiles) {
      final String? text = tree.textOf(path);
      if (text == null) {
        continue;
      }
      final List<String> lines = linesOf(text);
      for (int i = 0; i < lines.length; i++) {
        if (!_anyWayOut.hasMatch(lines[i]) || _isCommentOnly(lines[i])) {
          continue;
        }
        found.add(
          Finding(
            path,
            'reaches the machine directly rather than through a port: ${lines[i].trim()}',
            line: i + 1,
          ),
        );
      }
    }
    return found;
  }

  /// Whether [path] is one of the places the reach is allowed in the package holding it.
  bool _reachIsAllowedIn(String path) {
    // An infrastructure/ directory is where the reach belongs. The test is on a path segment, so a
    // file merely NAMED infrastructure.dart is not inside one.
    if (path.split('/').contains('infrastructure')) {
      return true;
    }
    for (final String directory in tree.packages.keys) {
      final String prefix = directory.isEmpty ? '' : '$directory/';
      for (final String outside in notTheShippedLibrary) {
        if (path.startsWith('$prefix$outside/')) {
          return true;
        }
      }
    }
    return false;
  }
}

/// Whether [line] is nothing but a comment.
///
/// Nothing executable can hide there: a comment-only line runs no code, and a trailing comment sits
/// on a line that is scanned anyway. The framework's own doc comments say what a port exists instead
/// of, and a scan that could not tell that from a call would forbid the sentence stating the rule.
bool _isCommentOnly(String line) {
  final String trimmed = line.trimLeft();
  return trimmed.startsWith('//') || trimmed.startsWith('*') || trimmed.startsWith('/*');
}

final RegExp _anyWayOut = RegExp('\\b(?:${waysOut.map(RegExp.escape).join('|')})\\b');
