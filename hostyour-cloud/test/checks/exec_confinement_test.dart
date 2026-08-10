import 'package:test/test.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

void main() {
  final ExecConfinement check = ExecConfinement(SourceTree.on(repositoryRoot()));

  test('this tree holds at least one Dart package', () {
    expect(
      check.tree.packages,
      isNotEmpty,
      reason: 'with no package there is nothing to confine and a pass would mean nothing',
    );
  });

  test('there is a shipped library to scan', () {
    expect(
      check.confinedFiles,
      isNotEmpty,
      reason:
          'every Dart file in this tree sits in one of the places the reach is allowed, so this '
          'check measured nothing',
    );
  });

  test('nothing in the shipped library outside infrastructure/ reaches the machine directly', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'the fix is to ask Shell, Files, Http or Clock rather than to widen this rule; only an '
          'infrastructure/ directory implements a port against the real machine',
    );
  });

  group('counter-probe', () {
    // Both directions, or the probe proves nothing: a planted reach outside infrastructure/ must be
    // reported, and the same line inside one must not. A scan that reported everything would pass
    // the first half alone.

    final ExecConfinement planted = ExecConfinement(
      SourceTree.planted(<String, String>{
        'pubspec.yaml': 'name: planted_package\n',
        'lib/src/steps/host/planted.dart': _reach,
        'lib/src/infrastructure/real_shell.dart': _reach,
        // lib/src/testing/ ships and only LOOKS like test/. If the allowances are ever collapsed
        // into a match on the word anywhere in the path, this file is what reports it.
        'lib/src/testing/fake_machine.dart': _reach,
        'test/checks/reads_a_program.dart': _reach,
        'bin/ansiwise.dart': _reach,
        'tool/ci.dart': _reach,
        'lib/src/steps/host/only_says_it.dart': _mentionsItInAComment,
      }),
    );
    final List<Finding> reported = planted.findings;

    for (final String path in <String>[
      'lib/src/steps/host/planted.dart',
      'lib/src/testing/fake_machine.dart',
    ]) {
      test('a planted reach in $path is reported', () {
        expect(
          about(reported, path),
          isNotEmpty,
          reason: 'this scan cannot go red there, so its silence about the real tree means nothing',
        );
      });
    }

    for (final String path in <String>[
      'lib/src/infrastructure/real_shell.dart',
      'test/checks/reads_a_program.dart',
      'bin/ansiwise.dart',
      'tool/ci.dart',
    ]) {
      test('the same lines in $path are not reported', () {
        expect(
          about(reported, path),
          isEmpty,
          reason: 'this scan refuses one of the places the reach belongs',
        );
      });
    }

    test('a line that only names the reach in a comment is not a reach', () {
      expect(
        about(reported, 'lib/src/steps/host/only_says_it.dart'),
        isEmpty,
        reason:
            "the framework's own doc comments say what a port exists instead of, and a scan that "
            'could not tell that from a call would forbid the sentence that states the rule',
      );
    });

    test('a finding names the line the reach sits on', () {
      expect(
        about(reported, 'lib/src/steps/host/planted.dart').map((Finding hit) => hit.line),
        contains(2),
        reason:
            'the finding is what an operator opens; without the line it names a file of unknown '
            'length',
      );
    });
  });
}

const String _reach =
    "import 'dart:io';\n"
    'Future<void> plantedApply() async => Process.run("rm", <String>["-rf", "/"]);';

const String _mentionsItInAComment =
    '/// Neither of these knows about a socket or dart:io, and none of them starts a Process.';
