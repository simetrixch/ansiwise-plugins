import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:test/test.dart';

/// One file composes every kubectl invocation, and this is what keeps that true.
///
/// The scan reports every quoted `'kubectl'` in a step file other than the composer's own. That
/// literal is how an invocation is spelled — as the executable of a command or as a word of an argv
/// list — so a step carrying it is a step assembling a kubectl command line of its own, which is
/// exactly the shape the composer exists to end: it is how a value lands on a command line, how
/// output parsing spreads, and how the question of WHICH client gets answered differently in
/// different files.
///
/// A quoted mention in a comment is reported too, and that is accepted: a step has no reason to
/// quote the word, and prose about the client writes it without quotes.
void main() {
  final List<Finding> reported = _spelledInvocations(SourceTree.on(repositoryRoot()));

  test('no step spells the kubectl invocation itself', () {
    expect(
      reported,
      isEmpty,
      reason:
          'the fix is to take a Kubectl from the arguments and compose the command line through '
          'it, never to spell the invocation in the step',
    );
  });

  group('counter-probe', () {
    // Both directions, or the probe proves nothing: a planted invocation must be reported, and the
    // same word in the composer and in prose must not.
    final List<Finding> planted = _spelledInvocations(
      SourceTree.planted(<String, String>{
        'pubspec.yaml': 'name: planted_package\n',
        'lib/src/steps/planted.dart': _spellsTheExecutable,
        'lib/src/steps/planted_word.dart': _spellsTheWordInAnArgvList,
        'lib/src/steps/kubectl.dart': _spellsTheExecutable,
        'lib/src/steps/only_says_it.dart': _mentionsItInProse,
      }),
    );

    for (final String path in <String>[
      'lib/src/steps/planted.dart',
      'lib/src/steps/planted_word.dart',
    ]) {
      test('a planted invocation in $path is reported', () {
        expect(
          about(planted, path),
          isNotEmpty,
          reason: 'this scan cannot go red there, so its silence about the real tree means nothing',
        );
      });
    }

    test('the composer itself is where the word belongs and is not reported', () {
      expect(about(planted, 'lib/src/steps/kubectl.dart'), isEmpty);
    });

    test('prose that names the client without quoting it is not reported', () {
      expect(about(planted, 'lib/src/steps/only_says_it.dart'), isEmpty);
    });

    test('a finding names the line the invocation sits on', () {
      expect(
        about(planted, 'lib/src/steps/planted.dart').map((Finding hit) => hit.line),
        contains(2),
        reason: 'without the line the finding names a file of unknown length',
      );
    });
  });
}

/// Every quoted `'kubectl'` in a step file of [tree], except in the composer's own file.
List<Finding> _spelledInvocations(SourceTree tree) {
  const String composer = 'lib/src/steps/kubectl.dart';
  final List<Finding> reported = <Finding>[];
  for (final String path in tree.dartFiles) {
    if (!path.startsWith('lib/src/steps/') || path == composer) {
      continue;
    }
    final List<String> lines = linesOf(tree.textOf(path) ?? '');
    for (int at = 0; at < lines.length; at += 1) {
      if (lines[at].contains(_quotedKubectl)) {
        reported.add(
          Finding(
            path,
            "spells 'kubectl' itself — the composer in $composer is the one place a kubectl "
            'invocation is put together',
            line: at + 1,
          ),
        );
      }
    }
  }
  return reported;
}

/// The literal an argv entry or an executable is spelled as.
final RegExp _quotedKubectl = RegExp("'kubectl'");

const String _spellsTheExecutable =
    'Future<void> plantedApply(StepContext context) async =>\n'
    "    context.shell.run(const Command('kubectl', <String>['get', 'nodes']));";

const String _spellsTheWordInAnArgvList =
    "const List<String> plantedArgv = <String>['kubectl', 'get', 'nodes'];";

const String _mentionsItInProse =
    '/// The client is kubectl, and this sentence names it without quoting it.';
