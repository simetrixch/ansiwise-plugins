/// naming — the abolished words appear in no name.
///
/// WHAT WAS ABOLISHED IS A PROGRAM NAME, NOT A VERB, and this distinction is the whole check. The
/// shell implementation this plugin replaced had `install.sh` and `setup.sh`: two programs split
/// along a line nobody could name, which is how one of them came to do five unrelated things. The
/// verbs for our programs are `deploy` and `onboard`, and what is deployed or onboarded is a `host`,
/// a `branch`, a `cluster`, `gitops` or the `controller`. So the two words are forbidden where a
/// program or a sub-command is named, and there only.
///
/// `install` as the name of what a command DOES is not abolished and must not be reported. A step
/// that runs `apt-get install` is called install_packages.dart because that is the word the software
/// itself uses, and the naming law of this project is to take that word rather than invent one. A
/// check that forbade the substring would rename the step to something that no longer says what it
/// runs — which is the failure this check exists to prevent, arriving from the other side.
///
/// THE ONE UNCONDITIONAL WORD IS `desktop`, in a file name, a directory name or a sub-command alike.
/// It is not a bad name, it is a false one: one client runs on web, on a phone, on a tablet and on a
/// laptop, so `desktop` states a platform the code inside it does not have. There is no position in
/// which that becomes true, so there is no position in which it is allowed.
///
/// A word can hide in three places a compiler never reads: a file name, a directory name, and the
/// string a sub-command answers to on the command line. Those are what this scans.
library;

import 'package:path/path.dart' as p;

import 'finding.dart';
import 'source_tree.dart';

/// The scan itself, over a tree it is given rather than over the repository it lives in.
final class Naming {
  /// Judges [tree], reading [roots] of it.
  Naming(this.tree, {Set<String> roots = const <String>{}})
    : roots = roots.isEmpty ? <String>{'tool', ...tree.packages.keys} : roots;

  /// The tree being judged.
  final SourceTree tree;

  /// What is scanned: the gate's own directory and every Dart package.
  ///
  /// The empty string is the whole tree, which is what the root package of this repository amounts
  /// to. Overlapping roots are a set of paths and not a list of scans, so a directory inside a
  /// package is judged once rather than once per root that contains it.
  final Set<String> roots;

  /// Every file and directory name the roots cover, sorted and each named once.
  List<String> get namesJudged {
    final Set<String> names = <String>{for (final String root in roots) ...tree.namesUnder(root)};
    return names.toList(growable: false)..sort();
  }

  /// Every Dart file the roots cover, sorted and each named once.
  List<String> get dartFilesJudged {
    final Set<String> paths = <String>{
      for (final String root in roots)
        for (final String path in tree.dartFiles)
          if (root.isEmpty || path == root || path.startsWith('$root/')) path,
    };
    return paths.toList(growable: false)..sort();
  }

  /// Every file or directory name carrying an abolished word.
  ///
  /// Four rules. `desktop` is the only test on the substring, for the reason above; the other three
  /// ask WHERE the name sits before they ask what it says, which is what keeps install_packages.dart
  /// out of the findings. Every test is case-insensitive, because `Setup` is the same word wearing a
  /// disguise.
  List<Finding> get nameFindings {
    final List<Finding> found = <Finding>[];
    for (final String path in namesJudged) {
      final String name = p.posix.basename(path).toLowerCase();

      if (name.contains(_falsePlatform)) {
        found.add(Finding(path, '$_falsePlatform names a platform the code does not have'));
        continue;
      }

      if (tree.directories.contains(path)) {
        // A directory CALLED install or setup is the old split by another route: it collects
        // whatever somebody decided belongs to installing, which is the grouping that had no name.
        if (abolishedPrograms.contains(name)) {
          found.add(
            Finding(path, 'a directory named for the abolished program, not for what is in it'),
          );
        }
        continue;
      }

      // The two shell programs themselves, and a Dart file that would inherit their names.
      if (_abolishedFileNames.contains(name)) {
        found.add(Finding(path, 'the abolished program name; the verbs are deploy and onboard'));
        continue;
      }

      // A program file is one that lives in a programs/ directory: its name is what an operator
      // picks from a list, so it is named like a sub-command and judged like one.
      if (SourceTree.directoryOf(path).split('/').contains('programs') &&
          abolishedPrograms.any(name.startsWith)) {
        found.add(Finding(path, 'a program named install/setup; the verbs are deploy and onboard'));
      }
    }
    return found;
  }

  /// Every Dart sub-command whose name carries an abolished word.
  ///
  /// A sub-command is declared in one of two shapes, and both are read out of the source rather than
  /// guessed at: `parser.addCommand('deploy-host')` for a bare ArgParser, and `String get name =>
  /// 'deploy-host'` for a Command subclass. A word that reaches the command line is what an operator
  /// types and reads in help output, so it outlives every rename of the file behind it.
  ///
  /// A sub-command is a program name, so `install`, `setup` and anything beginning with them is out.
  /// `desktop` is out wherever it sits in the string.
  List<Finding> get subCommandFindings {
    final List<Finding> found = <Finding>[];
    for (final String path in dartFilesJudged) {
      final String? text = tree.textOf(path);
      if (text == null) {
        continue;
      }
      final List<String> lines = linesOf(text);
      for (int i = 0; i < lines.length; i++) {
        if (_declaredCommand.firstMatch(lines[i])?.group(2) case final String declared) {
          final String name = declared.toLowerCase();
          if (abolishedPrograms.any(name.startsWith) || name.contains(_falsePlatform)) {
            found.add(
              Finding(path, 'the sub-command "$declared" carries an abolished word', line: i + 1),
            );
          }
        }
      }
    }
    return found;
  }

  /// Everything wrong with the names in this tree.
  List<Finding> get findings => <Finding>[...nameFindings, ...subCommandFindings];
}

/// The two abolished program names, lower case.
const Set<String> abolishedPrograms = <String>{'install', 'setup'};

const String _falsePlatform = 'desktop';

const Set<String> _abolishedFileNames = <String>{
  'install.sh',
  'setup.sh',
  'install.dart',
  'setup.dart',
};

/// The name a sub-command answers to, in either of the two shapes it is declared in.
///
/// The literal is taken from immediately behind the marker rather than as the first quoted thing on
/// the line, so a line that carries the marker inside a string of its own — which is what a
/// counter-probe writes — yields the string it actually declares.
final RegExp _declaredCommand = RegExp(r'''(?:addCommand\(\s*|get name\s*=>\s*)(['"])([^'"]*)\1''');
