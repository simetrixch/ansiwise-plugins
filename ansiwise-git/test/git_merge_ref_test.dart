import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// The step that brings a generated branch up to a stated commit by merging it in.
///
/// The property everything here circles is the declaration rule: a content conflict under a listed
/// pattern is taken from the incoming commit because a later row writes it again, and EVERY other
/// conflict — outside the patterns, or a deletion under them — aborts the merge and is named. A
/// merge that guessed there would guess exactly where guessing destroys somebody's record.
void main() {
  /// The commit the branch is brought up to, as a row would take it from a measurement.
  const String ref = 'v1.2.3';

  const GitMergeRef step = GitMergeRef(
    repository: repository,
    branchAnswer: nameAnswer,
    ref: ref,
    towardRef: <String>['rendered/*'],
  );

  /// A checkout standing on the branch, mid-history, with the commit resolvable and nothing dirty.
  FakeShell standing({String head = branch, bool carries = false, String status = ''}) {
    final FakeShell shell = FakeShell()
      ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$head\n')
      ..fails('git -C $repository rev-parse --verify --quiet MERGE_HEAD')
      ..answers('git -C $repository rev-parse --verify --quiet $ref^{commit}', 'abc123\n')
      ..answers('git -C $repository status --porcelain', status);
    if (carries) {
      shell.answers('git -C $repository merge-base --is-ancestor $ref HEAD', '');
    } else {
      shell.fails('git -C $repository merge-base --is-ancestor $ref HEAD');
    }
    return shell;
  }

  group('what has to be true before anything is merged', () {
    test('a checkout standing on the branch, with the commit resolvable, is ready', () async {
      expect(await step.check(contextOn(shell: standing())), isA<Ready>());
    });

    test('a branch already carrying the commit is the finished state, not an error', () async {
      final CheckResult answer = await step.check(contextOn(shell: standing(carries: true)));
      expect((answer as Satisfied).because, contains(ref));
    });

    test('a run holding no answer under the row\'s name is refused by that name', () async {
      final CheckResult answer = await step.check(contextOn(shell: standing(), name: null));
      expect((answer as Blocked).reason, contains(nameAnswer));
    });

    test('a row whose commit nothing measured yet is refused as that', () async {
      const GitMergeRef unmeasured = GitMergeRef(
        repository: repository,
        branchAnswer: nameAnswer,
        ref: '',
      );
      final CheckResult answer = await unmeasured.check(contextOn(shell: standing()));
      expect((answer as Blocked).reason, contains('measured'));
    });

    test('any other branch checked out is refused rather than moved off', () async {
      final CheckResult answer = await step.check(contextOn(shell: standing(head: 'master')));
      expect((answer as Blocked).reason, contains('"master"'));
      expect(answer.reason, contains(branch));
    });

    test('a commit the checkout cannot resolve is refused before any merge', () async {
      final FakeShell shell = standing()
        ..fails('git -C $repository rev-parse --verify --quiet $ref^{commit}');
      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('fetch'));
    });

    test('a dirty working tree is refused, naming what stands in it', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: standing(status: ' M rendered/one.yaml\n')),
      );
      expect((answer as Blocked).reason, contains('rendered/one.yaml'));
    });

    test('a merge already standing unfinished is refused rather than merged over', () async {
      final FakeShell shell = standing()
        ..answers('git -C $repository rev-parse --verify --quiet MERGE_HEAD', 'def456\n');
      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('in progress'));
    });

    test('the check only measures, and changes nothing', () async {
      final FakeShell shell = standing();
      await step.check(contextOn(shell: shell));
      expect(shell.commands.where((Command c) => !c.observes), isEmpty);
    });
  });

  group('where the commit comes from: the row writes it, or names the answer holding it', () {
    /// The name of the answer a row would point at, and — deliberately — not a word any product of
    /// ours uses, for the reason [nameAnswer] gives.
    const String refAnswerName = 'ref_name';

    const GitMergeRef answered = GitMergeRef(
      repository: repository,
      branchAnswer: nameAnswer,
      ref: '',
      refAnswer: refAnswerName,
    );

    test('the commit taken from the named answer drives the merge', () async {
      final FakeShell shell = standing()..answers('git -C $repository merge --no-edit $ref', '');

      await answered.apply(
        contextOn(shell: shell, also: const <String, Object>{refAnswerName: ref}),
      );
      expect(shell.ran, contains('git -C $repository merge --no-edit $ref'));
    });

    test('the commit written on the row drives the merge exactly as before', () async {
      final FakeShell shell = standing()..answers('git -C $repository merge --no-edit $ref', '');

      await step.apply(contextOn(shell: shell));
      expect(shell.ran, contains('git -C $repository merge --no-edit $ref'));
    });

    test('a row writing the commit AND naming an answer is refused by both names', () async {
      const GitMergeRef both = GitMergeRef(
        repository: repository,
        branchAnswer: nameAnswer,
        ref: ref,
        refAnswer: refAnswerName,
      );

      final CheckResult answer = await both.check(
        contextOn(shell: standing(), also: const <String, Object>{refAnswerName: ref}),
      );
      expect((answer as Blocked).reason, contains('"ref"'));
      expect(answer.reason, contains('"ref_answer"'));
    });

    test('a row giving the commit neither way is refused by both names', () async {
      const GitMergeRef neither = GitMergeRef(
        repository: repository,
        branchAnswer: nameAnswer,
        ref: '',
      );

      final CheckResult answer = await neither.check(contextOn(shell: standing()));
      expect((answer as Blocked).reason, contains('"ref"'));
      expect(answer.reason, contains('"ref_answer"'));
    });

    test('a run holding no answer under the row\'s name is refused by that name', () async {
      final CheckResult answer = await answered.check(contextOn(shell: standing()));
      expect((answer as Blocked).reason, contains(refAnswerName));
    });
  });

  group('the merge itself', () {
    test('a clean merge is the one command and nothing after it', () async {
      final FakeShell shell = standing()..answers('git -C $repository merge --no-edit $ref', '');

      await step.apply(contextOn(shell: shell));
      expect(shell.ran, contains('git -C $repository merge --no-edit $ref'));
      expect(shell.ran.where((String c) => c.contains('merge --abort')), isEmpty);
    });

    test('a content conflict under a listed pattern is taken from the incoming commit', () async {
      final FakeShell shell = standing()
        ..fails('git -C $repository merge --no-edit $ref', stderr: 'CONFLICT (content)')
        ..answers('git -C $repository diff --name-only --diff-filter=U', 'rendered/one.yaml\n')
        ..answers(
          'git -C $repository ls-files -u -- rendered/one.yaml',
          '100644 aaa 1\trendered/one.yaml\n'
              '100644 bbb 2\trendered/one.yaml\n'
              '100644 ccc 3\trendered/one.yaml\n',
        );

      await step.apply(contextOn(shell: shell));
      expect(shell.ran, contains('git -C $repository checkout --theirs -- rendered/one.yaml'));
      expect(shell.ran, contains('git -C $repository add -- rendered/one.yaml'));
      expect(shell.ran, contains('git -C $repository commit --no-edit'));
    });

    test('a conflict outside every pattern aborts the merge and is named', () async {
      final FakeShell shell = standing()
        ..fails('git -C $repository merge --no-edit $ref', stderr: 'CONFLICT (content)')
        ..answers(
          'git -C $repository diff --name-only --diff-filter=U',
          'rendered/one.yaml\nrecords/kept.yaml\n',
        )
        ..answers(
          'git -C $repository ls-files -u -- rendered/one.yaml',
          '100644 aaa 1\trendered/one.yaml\n'
              '100644 bbb 2\trendered/one.yaml\n'
              '100644 ccc 3\trendered/one.yaml\n',
        )
        ..answers(
          'git -C $repository ls-files -u -- records/kept.yaml',
          '100644 aaa 1\trecords/kept.yaml\n'
              '100644 bbb 2\trecords/kept.yaml\n'
              '100644 ccc 3\trecords/kept.yaml\n',
        );

      await expectLater(
        step.apply(contextOn(shell: shell)),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('records/kept.yaml'),
          ),
        ),
      );
      expect(shell.ran, contains('git -C $repository merge --abort'));
      expect(
        shell.ran.where((String c) => c.contains('commit --no-edit')),
        isEmpty,
        reason: 'a merge that was aborted must not be committed',
      );
    });

    test(
      'a deletion under a listed pattern still aborts — a pattern licenses content only',
      () async {
        final FakeShell shell = standing()
          ..fails('git -C $repository merge --no-edit $ref', stderr: 'CONFLICT (modify/delete)')
          ..answers('git -C $repository diff --name-only --diff-filter=U', 'rendered/gone.yaml\n')
          ..answers(
            'git -C $repository ls-files -u -- rendered/gone.yaml',
            '100644 aaa 1\trendered/gone.yaml\n'
                '100644 bbb 2\trendered/gone.yaml\n',
          );

        await expectLater(step.apply(contextOn(shell: shell)), throwsA(isA<StateError>()));
        expect(shell.ran, contains('git -C $repository merge --abort'));
        expect(
          shell.ran.where((String c) => c.contains('checkout --theirs')),
          isEmpty,
          reason: 'there is no incoming content to take for a deletion',
        );
      },
    );

    test('a merge that failed with no conflict at all fails with its own words', () async {
      final FakeShell shell = standing()
        ..fails('git -C $repository merge --no-edit $ref', stderr: 'fatal: refusing to merge')
        ..answers('git -C $repository diff --name-only --diff-filter=U', '');

      await expectLater(step.apply(contextOn(shell: shell)), throwsA(isA<CommandFailed>()));
    });
  });

  group('the undo steps back over exactly the merge this step made', () {
    test('an unfinished merge is aborted', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --verify --quiet MERGE_HEAD', 'def456\n')
        ..answers('git -C $repository rev-parse HEAD', 'abc\n');

      await step.undo(contextOn(shell: shell), 'abc');
      expect(shell.ran, contains('git -C $repository merge --abort'));
    });

    test('a merge commit whose first parent is the captured commit is reset away', () async {
      final FakeShell shell = FakeShell()
        ..fails('git -C $repository rev-parse --verify --quiet MERGE_HEAD')
        ..answers('git -C $repository rev-parse HEAD', 'merged\n')
        ..answers('git -C $repository rev-parse HEAD^1', 'abc\n');

      await step.undo(contextOn(shell: shell), 'abc');
      expect(shell.ran, contains('git -C $repository reset --hard abc'));
    });

    test('a head somebody moved further is left alone', () async {
      final FakeShell shell = FakeShell()
        ..fails('git -C $repository rev-parse --verify --quiet MERGE_HEAD')
        ..answers('git -C $repository rev-parse HEAD', 'later\n')
        ..answers('git -C $repository rev-parse HEAD^1', 'merged\n');

      await step.undo(contextOn(shell: shell), 'abc');
      expect(shell.ran.where((String c) => c.contains('reset --hard')), isEmpty);
    });
  });
}
