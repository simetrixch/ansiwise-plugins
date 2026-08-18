import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Cutting one branch from another, and the five things that stop it.
void main() {
  const GitBranch step = GitBranch(repository: repository, base: base, nameAnswer: nameAnswer);

  group('the branch is cut from the one this checkout stands on', () {
    test('from the base, with a clean tree, there is work to do', () async {
      expect(await step.check(contextOn(shell: checkout())), isA<Ready>());
    });

    test('the branch is what apply produces, and the check afterwards proves it', () async {
      final FakeShell shell = checkout();
      shell.changes('git -C $repository checkout -b $branch', () {
        shell.answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n');
      });
      final StepContext context = contextOn(shell: shell);

      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run on the branch does nothing at all', () async {
      final FakeShell shell = checkout(head: branch);
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect(answer, isA<Satisfied>());
      expect(shell.ran, isNot(contains('git -C $repository checkout -b $branch')));
    });

    test('a branch that already exists is reported, never reset', () async {
      final FakeShell shell = checkout(branchExists: true);
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect((answer as Blocked).reason, contains('already exists'));
      expect(shell.commands.where((Command c) => !c.observes), isEmpty);
    });

    test('a dirty tree is refused, because the branch would carry it', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: checkout(status: ' M values.yaml\n')),
      );
      expect((answer as Blocked).reason, contains('values.yaml'));
    });

    test('a branch that is neither the base nor this one is refused', () async {
      final CheckResult answer = await step.check(contextOn(shell: checkout(head: 'other-work')));
      expect((answer as Blocked).reason, contains('other-work'));
    });

    test('a detached head is refused as having no branch to cut from', () async {
      final FakeShell shell = checkout()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'HEAD\n');

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('no branch checked out'));
    });
  });

  group('the name comes from the answer the row points at', () {
    test('a run that holds no such answer is refused, and the answer is named', () async {
      final FakeShell shell = checkout();
      final CheckResult answer = await step.check(contextOn(shell: shell, name: null));

      expect((answer as Blocked).reason, contains(nameAnswer));
      expect(shell.ran, isEmpty, reason: 'there is no branch to ask a machine anything about');
    });

    test('the row decides which answer, and nothing here assumes one', () async {
      // The step reads whatever name its row gives it. A step that reached for a name of its own
      // would pass every case above and fail on the first product that calls its answer something
      // else.
      const GitBranch other = GitBranch(
        repository: repository,
        base: base,
        nameAnswer: 'somewhere_else',
      );
      final FakeShell shell = checkout(name: 'cut-from-elsewhere');
      final StepContext context = contextOn(
        shell: shell,
        name: 'cut-from-elsewhere',
        answerName: 'somewhere_else',
      );

      expect(await other.check(context), isA<Ready>());
      expect((await other.plan(context) as ArgvPlan).argv, contains('cut-from-elsewhere'));
    });

    test('a name git would reject is refused before the checkout is read', () async {
      // What is a legal branch name is git's own answer, asked of git. A grammar restated here
      // would agree with git on the day it was written and drift from then on.
      final FakeShell shell = checkout(name: 'two words')
        ..fails(
          'git check-ref-format --branch two words',
          exitCode: 128,
          stderr: "fatal: 'two words' is not a valid branch name",
        );

      final CheckResult answer = await step.check(contextOn(shell: shell, name: 'two words'));
      expect((answer as Blocked).reason, contains('not a valid branch name'));
      expect(answer.reason, contains(nameAnswer));
      expect(
        shell.ran,
        isNot(contains('git -C $repository rev-parse --abbrev-ref HEAD')),
        reason: 'a name git will not take makes every later question about it pointless',
      );
    });
  });

  group('taking it back', () {
    test('it returns to what was checked out and removes the branch', () async {
      // The captured value is what was checked out before this step cut the branch, so the undo
      // returns there rather than to a name it composed.
      final FakeShell shell = checkout(head: branch);
      await step.undo(contextOn(shell: shell), base);

      expect(shell.ran, contains('git -C $repository checkout $base'));
      expect(shell.ran, contains('git -C $repository branch -D $branch'));
    });

    test('it leaves a branch this step did not produce alone', () async {
      final FakeShell shell = checkout(head: 'other-work');
      await step.undo(contextOn(shell: shell), base);

      expect(shell.ran, isNot(contains('git -C $repository branch -D $branch')));
    });
  });
}
