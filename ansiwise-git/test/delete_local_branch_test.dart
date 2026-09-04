import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Deleting the local branch of a run, and putting it back.
void main() {
  const DeleteLocalBranch step = DeleteLocalBranch(repository: repository, nameAnswer: nameAnswer);

  /// The reading that says whether this checkout carries the branch, and where it stands.
  const String standing = 'git -C $repository rev-parse --verify --quiet refs/heads/$branch';

  /// What `checkout(branchExists: true)` answers for it.
  const String tip = 'abc';

  const String deleting = 'git -C $repository branch -D $branch';

  group('the local branch is taken away', () {
    test('a checkout carrying the branch has work to do', () async {
      expect(await step.check(contextOn(shell: checkout(branchExists: true))), isA<Ready>());
    });

    test('applied, the branch is gone and a second run has nothing to do', () async {
      final FakeShell shell = checkout(branchExists: true);
      shell.changes(deleting, () => shell.fails(standing));
      final StepContext context = contextOn(shell: shell);

      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(shell.ran.where((String each) => each == deleting).length, 1);
    });

    test('a checkout carrying no such branch is satisfied without a command', () async {
      final FakeShell shell = checkout();
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect(answer, isA<Satisfied>());
      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });

    test('nothing here sends anything to a remote', () async {
      final FakeShell shell = checkout(branchExists: true);
      await step.apply(contextOn(shell: shell));

      expect(shell.ran, contains(deleting));
      expect(
        shell.ran.where((String each) => each.contains('push')),
        isEmpty,
        reason: 'a published branch is one other machines have already resolved',
      );
    });
  });

  group('what it refuses', () {
    test('a reading that was refused, rather than reporting a branch already gone', () async {
      // Exit one is git saying the ref resolves to nothing. Every other non-zero exit is git not
      // having answered at all, and folded into the same null it would report this row finished over
      // a checkout nobody could read.
      final FakeShell shell = checkout()
        ..fails(standing, exitCode: 128, stderr: 'fatal: not a git repository');

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('could not be read'));
      expect(answer.reason, contains('not a git repository'));
    });

    test('the branch this checkout is standing on', () async {
      final FakeShell shell = checkout(head: branch, branchExists: true);
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect((answer as Blocked).reason, contains('stands on "$branch"'));
      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });

    test('a run that holds no such answer, and the answer is named', () async {
      final FakeShell shell = checkout(branchExists: true);
      final CheckResult answer = await step.check(contextOn(shell: shell, name: null));

      expect((answer as Blocked).reason, contains(nameAnswer));
      expect(shell.ran, isEmpty);
    });
  });

  group('taking it back', () {
    test('the branch is cut again at the commit it stood on', () async {
      final FakeShell shell = checkout(branchExists: true);
      final StepContext context = contextOn(shell: shell);

      final String? captured = await step.capture(context);
      expect(captured, tip);
      await step.undo(context, captured);

      expect(shell.ran, contains('git -C $repository branch $branch $tip'));
    });

    test('a branch that was not there is not cut by the undo', () async {
      final FakeShell shell = checkout();
      final StepContext context = contextOn(shell: shell);

      expect(await step.capture(context), isNull);
      await step.undo(context, null);
      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });

    test('a capture that could not read leaves the branch alone and says so', () async {
      final FakeShell shell = checkout()
        ..fails(standing, exitCode: 128, stderr: 'fatal: not a git repository');
      final RecordingLog log = RecordingLog();
      final StepContext context = contextOn(shell: shell, log: log);

      expect(await step.capture(context), isNull);
      expect(log.warnings.single, contains('not a git repository'));

      await step.undo(context, null);
      expect(shell.commands.where((Command each) => !each.observes), isEmpty);
    });
  });
}
