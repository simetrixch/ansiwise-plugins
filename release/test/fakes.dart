/// The git and the manifests a check drives the release program over.
///
/// WHAT CANNOT BE SHOWN BY RUNNING IT. A real accepted run pushes a commit and a tag to GitHub,
/// which no check may do, and a release is not something to be started by a suite. So the deciding
/// half is driven over a git that is a script and manifests that are values: what the program asked
/// for is then a list of argument lists in the order it asked, and both claims of this program are
/// readable in it — the screen RUNS ONLY READS, and a version and a channel that are typed reach
/// `git push` as the last command and not before.
library;

import '../tool/release_git.dart';
import '../tool/release_packages.dart';

/// A git that answers what it was told to and remembers what it was asked.
final class ScriptedGit implements Git {
  /// Answers [answers] to the commands whose arguments joined by a space are its keys, and
  /// [otherwise] to everything else.
  ScriptedGit({
    this.answers = const <String, GitAnswer>{},
    this.otherwise = const GitAnswer(status: 0, output: ''),
  });

  /// What is answered to the commands whose arguments joined by a space are its keys.
  final Map<String, GitAnswer> answers;

  /// What is answered to a command nothing was scripted for.
  final GitAnswer otherwise;

  /// Every command that was run, in the order it was run.
  final List<List<String>> asked = <List<String>>[];

  /// Every command that was run, each as one line of text.
  List<String> get spelled => asked.map((List<String> each) => each.join(' ')).toList();

  @override
  Future<GitAnswer> run(List<String> arguments) async {
    asked.add(arguments);
    return answers[arguments.join(' ')] ?? otherwise;
  }
}

/// Manifests that are values rather than files, and remember what was written into them.
final class ManifestsInMemory implements Manifests {
  /// The manifests [texts] holds, listed in the order its keys stand.
  ManifestsInMemory(this.texts);

  /// What each manifest holds now — a write replaces the entry.
  final Map<String, String> texts;

  /// The paths that were written to, in the order they were written.
  final List<String> written = <String>[];

  @override
  List<String> get paths => texts.keys.toList(growable: false);

  @override
  String? read(String path) => texts[path];

  @override
  void write(String path, String text) {
    written.add(path);
    texts[path] = text;
  }
}

/// A pubspec declaring [name] at [version], optionally depending on the siblings [dependsOn].
///
/// The shape is the one this repository's own manifests carry, `path:` after `ref:` — and one of the
/// dependencies is written the other way round on purpose, because ansiwise-cli's pubspec.yaml
/// really does spell one of its eleven that way and a reader that only handled one order would pass
/// every check written by whoever wrote the reader.
String plantedPubspec({
  required String name,
  String? version,
  Map<String, String> dependsOn = const <String, String>{},
  bool pathBeforeRef = false,
}) {
  final StringBuffer pubspec = StringBuffer()
    ..writeln('name: $name')
    ..writeln('publish_to: none');
  if (version != null) {
    pubspec.writeln('version: $version');
  }
  pubspec
    ..writeln('')
    ..writeln('dependencies:');
  for (final MapEntry<String, String> entry in dependsOn.entries) {
    pubspec
      ..writeln('  ${entry.key}:')
      ..writeln('    git:')
      ..writeln('      url: https://github.com/simetrixch/ansiwise-plugins.git');
    if (pathBeforeRef) {
      pubspec
        ..writeln('      path: ${entry.value}')
        ..writeln('      ref: master');
    } else {
      pubspec
        ..writeln('      ref: master')
        ..writeln('      path: ${entry.value}');
    }
  }
  return pubspec.toString();
}
