import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Standing a checkout on a branch the remote already publishes.
void main() {
  const GitCheckoutBranch step = GitCheckoutBranch(
    repository: repository,
    remote: remote,
    nameAnswer: nameAnswer,
  );

  /// What the remote publishes the branch on.
  const String tip = 'a1a1a1';

  /// The fetch and the placement, as this step composes them.
  const String fetching =
      'git -C $repository fetch $remote +refs/heads/$branch:refs/remotes/$remote/$branch';
  const String placing = 'git -C $repository checkout -B $branch $remote/$branch';

  /// The reading that says where the local branch stands.
  const String localTip =
      'git -C $repository rev-parse --quiet --verify refs/heads/$branch^{commit}';

  /// A checkout whose remote publishes the branch, and which does not carry it yet.
  FakeShell publishing({String head = base, String status = ''}) =>
      checkout(head: head, status: status)
        ..answers(
          'git -C $repository ls-remote --heads $remote refs/heads/$branch',
          '$tip\trefs/heads/$branch\n',
        )
        ..fails(localTip);

  group('the branch the remote publishes is what the checkout is stood on', () {
    test('a checkout standing elsewhere has work to do', () async {
      expect(await step.check(contextOn(shell: publishing())), isA<Ready>());
    });

    test('applied, the check answers satisfied and a second run runs nothing', () async {
      final FakeShell shell = publishing();
      shell
        ..changes(fetching, () {
          shell.answers(
            'git -C $repository rev-parse --quiet --verify refs/remotes/$remote/$branch^{commit}',
            '$tip\n',
          );
        })
        ..changes(placing, () {
          shell
            ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n')
            ..answers(localTip, '$tip\n');
        });
      final StepContext context = contextOn(shell: shell);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());

      final int placed = shell.commands.where((Command each) => !each.observes).length;
      expect(await step.check(context), isA<Satisfied>());
      expect(
        shell.commands.where((Command each) => !each.observes).length,
        placed,
        reason: 'a second run finds the branch already placed and asks the machine for nothing',
      );
    });

    test('a checkout on the branch but behind the published tip is placed again', () async {
      final FakeShell shell = publishing(head: branch)..answers(localTip, 'older\n');
      expect(await step.check(contextOn(shell: shell)), isA<Ready>());
    });
  });

  group('what it refuses', () {
    test('a remote publishing no such branch, because this row does not cut one', () async {
      final FakeShell shell = checkout()
        ..answers('git -C $repository ls-remote --heads $remote refs/heads/$branch', '');

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('publishes no branch called "$branch"'));
    });

    test('a remote that could not be asked, rather than reading it as publishing none', () async {
      // The two are the same empty text on the way back, and only the exit code tells them apart. A
      // refusal read as "it publishes none" would send the run to the row that CUTS the branch, on
      // top of one that is already published.
      final FakeShell shell = checkout()
        ..fails(
          'git -C $repository ls-remote --heads $remote refs/heads/$branch',
          exitCode: 128,
          stderr: 'fatal: could not read Username',
        );

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('could not be asked'));
      expect(answer.reason, contains('could not read Username'));
    });

    test('a longer branch ending in this name is not this branch', () async {
      final FakeShell shell = checkout()
        ..answers(
          'git -C $repository ls-remote --heads $remote refs/heads/$branch',
          'c3c3c3\trefs/heads/work/$branch\n',
        );

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('publishes no branch called "$branch"'));
    });

    test('a working tree that is not clean, naming what stands in it', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: publishing(status: ' M values.yaml\n')),
      );
      expect((answer as Blocked).reason, contains('values.yaml'));
    });

    test('a checkout that is not there', () async {
      final FakeShell shell = checkout()
        ..fails('git -C $repository rev-parse --abbrev-ref HEAD', exitCode: 128);

      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('which branch it stands on'));
    });

    test('a run that holds no such answer, and the answer is named', () async {
      final FakeShell shell = publishing();
      final CheckResult answer = await step.check(contextOn(shell: shell, name: null));

      expect((answer as Blocked).reason, contains(nameAnswer));
      expect(shell.ran, isEmpty, reason: 'there is no branch to ask a machine anything about');
    });
  });

  test('the row decides which answer, and nothing here assumes one', () async {
    const GitCheckoutBranch other = GitCheckoutBranch(
      repository: repository,
      remote: remote,
      nameAnswer: 'somewhere_else',
    );
    final FakeShell shell = checkout(name: 'from-elsewhere')
      ..answers(
        'git -C $repository ls-remote --heads $remote refs/heads/from-elsewhere',
        'd4d4d4\trefs/heads/from-elsewhere\n',
      );
    final StepContext context = contextOn(
      shell: shell,
      name: 'from-elsewhere',
      answerName: 'somewhere_else',
    );

    expect(await other.check(context), isA<Ready>());
    expect((await other.plan(context) as ArgvPlan).argv, contains('from-elsewhere'));
  });
}
