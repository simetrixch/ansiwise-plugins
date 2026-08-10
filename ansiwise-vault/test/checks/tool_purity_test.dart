import 'dart:io';

import 'package:test/test.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

/// tool-purity — this plugin knows Vault the tool and never an application of it.
///
/// The vault plugin knows how a Vault is initialized, unsealed and shaped over its HTTP API —
/// mounts, policies, roles and entries are Vault's own words. What it may never know is any one
/// product's layout: where its profile stands, which keys that profile carries, which mounts and
/// policies exist under which names — every such name belongs to a program row, never to this
/// package.
///
/// So the scan reads every byte of lib/ and test/ — code, comment and fixture alike — against the
/// word list in tool/tool-purity.words. The test that decides a word stands at the head of that
/// list: could a vendor with the same tool and a completely different product still use this
/// package with that word in it?
///
/// The platform plugin in this repository is deliberately NOT scanned and carries no check of this
/// kind: it IS an application of these tools — naming its own platform is its job — so the rule
/// this check decides does not exist for it.
///
/// tool/ is not scanned, and that is the harness rather than a loophole. This check has to name
/// the words it forbids in order to search for them, and nothing under tool/ is compiled into the
/// plugin or shipped with it. It is also why the list of words is a file there rather than a
/// constant here: a list written into this file would be an occurrence of every word on it.
void main() {
  final Directory root = repositoryRoot();
  final List<String> forbidden = forbiddenWords(root);
  final SourceTree tree = SourceTree.on(root);

  test('the list of words this check searches for is not empty', () {
    expect(
      forbidden,
      isNotEmpty,
      reason:
          '$wordListPath is the whole of what this check looks for; an empty list scans for '
          'nothing and would pass over any tree at all',
    );
  });

  test('there is something under ${scannedPaths.join(', ')} to scan', () {
    expect(
      scannedFilesOf(tree),
      isNotEmpty,
      reason:
          'none of ${scannedPaths.join(', ')} is in this tree, so a pass here would mean nothing',
    );
  });

  test('this plugin names no application of its tool in ${scannedPaths.join(', ')}', () {
    expect(
      occurrencesOfForbiddenWords(tree, forbidden),
      isEmpty,
      reason:
          'each finding reads <file>:<line>:<text>, and the fix is to demote the name into a '
          'required argument whose value stands in the program row of the product that owns it',
    );
  });

  group('counter-probe', () {
    // A check that cannot go red proves nothing about the tree it passes on, so the same scan runs
    // again over trees this test writes, carrying the violations it must report and the innocent
    // neighbours it must leave alone.

    test('every word on the list is reported where it is planted', () {
      for (final String word in forbidden) {
        final SourceTree planted = SourceTree.planted(<String, String>{
          'lib/planted.dart': '/// Runs $word on the way to the target state.',
        });
        expect(
          occurrencesOfForbiddenWords(planted, forbidden),
          hasLength(1),
          reason:
              "a planted occurrence of '$word' was not reported, so this scan cannot go red on a "
              'word it claims to forbid',
        );
      }
    });

    test('a word buried inside a longer one is not an occurrence of it', () {
      for (final String word in forbidden) {
        final SourceTree planted = SourceTree.planted(<String, String>{
          'lib/innocent.dart': "const String value = 'before${word}after';",
        });
        expect(
          occurrencesOfForbiddenWords(planted, forbidden),
          isEmpty,
          reason:
              "the word-anchoring is gone: 'before${word}after' was read as an occurrence of "
              "'$word', which would forbid names this plugin may legitimately use",
        );
      }
    });

    test('an underscore ends the word, so a SCREAMING_SNAKE name is not a hiding place', () {
      // The shape this closes: an environment variable, a shell-ish constant, a fixture key. `\b`
      // would count the underscore as part of the word and pass over every one of them, so the
      // scan's answer would rest on which separator the author happened to type.
      for (final String word in forbidden) {
        for (final String planted in <String>['${word}_addr', 'the_$word', '$word-addr']) {
          expect(
            occurrencesOfForbiddenWords(
              SourceTree.planted(<String, String>{
                'lib/planted.dart': "const String value = '$planted';",
              }),
              forbidden,
            ),
            hasLength(1),
            reason:
                "'$planted' names '$word' as plainly as the bare word does, and was not reported",
          );
        }
      }
    });

    test('a file deep under lib/src is reported, so no exempt path has grown back', () {
      final SourceTree planted = SourceTree.planted(<String, String>{
        'lib/src/steps/deep.dart': _everyWordIn(forbidden),
      });
      expect(occurrencesOfForbiddenWords(planted, forbidden), isNotEmpty);
    });

    test('a file under test/ is reported, so test/ has not fallen out of scope', () {
      final SourceTree planted = SourceTree.planted(<String, String>{
        'test/planted_test.dart': _everyWordIn(forbidden),
      });
      expect(occurrencesOfForbiddenWords(planted, forbidden), isNotEmpty);
    });

    test('a file under tool/ is not scanned, or this check would report itself', () {
      final SourceTree planted = SourceTree.planted(<String, String>{
        'tool/tool-purity.words': _everyWordIn(forbidden),
        'tool/gate/planted.dart': _everyWordIn(forbidden),
      });
      expect(
        occurrencesOfForbiddenWords(planted, forbidden),
        isEmpty,
        reason:
            'tool/ holds the word list, which has to name what it forbids; scanning it makes this '
            'check impossible to pass',
      );
    });
  });
}

/// The directories of the package that are scanned.
///
/// Named one at a time rather than as "the package minus tools", so adding a directory to the
/// scan is a decision somebody makes here rather than a silent widening.
const List<String> scannedPaths = <String>['lib', 'test'];

/// Where the words live, relative to the package root.
const String wordListPath = 'tool/tool-purity.words';

/// The words this plugin may not name, read from [wordListPath] under [root].
List<String> forbiddenWords(Directory root) {
  final File file = File(
    <String>[root.path, ...wordListPath.split('/')].join(Platform.pathSeparator),
  );
  if (!file.existsSync()) {
    throw StateError(
      '$wordListPath is missing, so this check has nothing to search for and its silence would '
      'mean nothing',
    );
  }
  return <String>[
    for (final String line in linesOf(file.readAsStringSync()))
      if (line.trim().isNotEmpty && !line.trimLeft().startsWith('#')) line.trim(),
  ];
}

/// The files of [tree] that this check reads, sorted.
List<String> scannedFilesOf(SourceTree tree) =>
    tree.files.keys.where(_isScanned).toList(growable: false)..sort();

/// Every occurrence of a word of [words] in [tree], as `<file>:<line>:<text>`.
///
/// Matched case-insensitively, because the words appear as prose as often as identifiers, and
/// anchored on letters and digits, so a longer name that merely contains one is left alone.
///
/// The anchor is written out rather than left to `\b`, and the difference is the underscore. `\b`
/// counts it as part of a word, so a word followed by `_ADDR` would not match — and SCREAMING_SNAKE
/// is exactly where such a name arrives, because that is the shape of an environment variable.
/// Anything that is not a letter or a digit ends the word here, so `<word>_ADDR`, `<word>-addr` and
/// `<word>.addr` are each an occurrence, while `<word>ish` is not.
List<String> occurrencesOfForbiddenWords(SourceTree tree, List<String> words) {
  if (words.isEmpty) {
    return const <String>[];
  }
  final RegExp anyOfThem = RegExp(
    '(?<![A-Za-z0-9])(?:${words.map(RegExp.escape).join('|')})(?![A-Za-z0-9])',
    caseSensitive: false,
  );
  final List<String> found = <String>[];
  for (final String path in scannedFilesOf(tree)) {
    final String? text = tree.textOf(path);
    if (text == null) {
      continue;
    }
    final List<String> lines = linesOf(text);
    for (int i = 0; i < lines.length; i++) {
      if (anyOfThem.hasMatch(lines[i])) {
        found.add('$path:${i + 1}:${lines[i]}');
      }
    }
  }
  return found;
}

bool _isScanned(String path) =>
    scannedPaths.any((String root) => path == root || path.startsWith('$root/'));

/// A file body naming every word of [words], built at run time so this source carries none of them.
String _everyWordIn(List<String> words) =>
    words.map((String word) => '/// It reaches for $word.').join('\n');
