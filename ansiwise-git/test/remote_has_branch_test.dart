import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Asking a remote whether it publishes the branch this run names, both ways round.
void main() {
  const RemoteHasBranch carrying = RemoteHasBranch(
    repository: repository,
    remote: remote,
    nameAnswer: nameAnswer,
  );
  const RemoteHasBranch lacking = RemoteHasBranch(
    repository: repository,
    remote: remote,
    nameAnswer: nameAnswer,
    holdsWhenPublished: false,
  );

  const String asking = 'git -C $repository ls-remote --heads $remote refs/heads/$branch';

  group('what the remote publishes decides both shapes', () {
    test('a published branch holds the one shape and not the other', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isTrue);
      expect((await lacking.evaluate(contextOn(shell: shell))).held, isFalse);
    });

    test('a remote publishing none holds the other shape', () async {
      final FakeShell shell = checkout()..answers(asking, '');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isFalse);
      expect((await lacking.evaluate(contextOn(shell: shell))).held, isTrue);
    });

    test('both directions say what the remote said', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).because, contains(branch));
      expect((await lacking.evaluate(contextOn(shell: shell))).because, contains(branch));
    });

    test('a longer branch ending in this name is not this branch', () async {
      final FakeShell shell = checkout()..answers(asking, 'f6f6f6\trefs/heads/work/$branch\n');

      expect((await carrying.evaluate(contextOn(shell: shell))).held, isFalse);
    });

    test('it changes nothing', () async {
      final FakeShell shell = checkout()..answers(asking, 'e5e5e5\trefs/heads/$branch\n');
      await carrying.evaluate(contextOn(shell: shell));

      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });
  });

  group('what it refuses to answer at all', () {
    test('a remote that could not be asked, in BOTH shapes', () async {
      // The refusal has to reach both, or the shape that reads "it publishes none" would turn a
      // remote nobody reached into a decision to cut a branch on top of one already published.
      final FakeShell shell = checkout()
        ..fails(asking, exitCode: 128, stderr: 'fatal: could not read Username');

      expect(
        () => carrying.evaluate(contextOn(shell: shell)),
        throwsA(isA<ConditionUnanswerable>()),
      );
      expect(
        () => lacking.evaluate(contextOn(shell: shell)),
        throwsA(isA<ConditionUnanswerable>()),
      );
    });

    test('the refusal names the remote, the branch and what git said', () async {
      final FakeShell shell = checkout()
        ..fails(asking, exitCode: 128, stderr: 'fatal: could not read Username');

      await expectLater(
        () => carrying.evaluate(contextOn(shell: shell)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            allOf(contains(remote), contains(branch), contains('could not read Username')),
          ),
        ),
      );
    });

    test('a run holding no answer under the name it was pointed at', () async {
      final FakeShell shell = checkout();

      await expectLater(
        () => carrying.evaluate(contextOn(shell: shell, name: null)),
        throwsA(
          isA<ConditionUnanswerable>().having(
            (ConditionUnanswerable refusal) => refusal.because,
            'because',
            contains(nameAnswer),
          ),
        ),
      );
      expect(shell.ran, isEmpty, reason: 'there is no branch to ask a remote about');
    });
  });

  test('the configuration decides which answer, and nothing here assumes one', () async {
    const RemoteHasBranch other = RemoteHasBranch(
      repository: repository,
      remote: remote,
      nameAnswer: 'somewhere_else',
    );
    final FakeShell shell = checkout()
      ..answers(
        'git -C $repository ls-remote --heads $remote refs/heads/from-elsewhere',
        'a7a7a7\trefs/heads/from-elsewhere\n',
      );

    final PredicateResult answer = await other.evaluate(
      contextOn(shell: shell, name: 'from-elsewhere', answerName: 'somewhere_else'),
    );
    expect(answer.held, isTrue);
  });
}
