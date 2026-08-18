import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// What has to be true about a checkout before anything is written into it.
///
/// Both refusals exist because a run used to get all the way to the end and fail there: no committer
/// identity discovered at the commit, no write access discovered at the push.
void main() {
  group('a commit needs somebody to be made as', () {
    test('a name and a mailbox are enough', () async {
      final CheckResult answer = await const RequireGitIdentity(
        repository,
      ).check(contextOn(shell: checkout()));
      expect(answer, isA<Satisfied>());
    });

    test('both missing are named at once, not one per run', () async {
      final FakeShell shell = checkout()
        ..fails('git -C $repository config --get user.name')
        ..fails('git -C $repository config --get user.email');

      final CheckResult answer = await const RequireGitIdentity(
        repository,
      ).check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('user.name'));
      expect(answer.reason, contains('user.email'));
    });

    test('a value set to nothing is not a value', () async {
      final FakeShell shell = checkout()
        ..answers('git -C $repository config --get user.email', '   \n');

      final CheckResult answer = await const RequireGitIdentity(
        repository,
      ).check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('user.email'));
      expect(answer.reason, isNot(contains('user.name')));
    });

    test('a path that is no checkout is refused as that, not as a missing identity', () async {
      final FakeShell shell = checkout()..fails('git -C $repository rev-parse --git-dir');

      final CheckResult answer = await const RequireGitIdentity(
        repository,
      ).check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('no git checkout'));
      expect(answer.reason, isNot(contains('user.name')));
    });

    test('it only measures, and changes nothing', () async {
      final FakeShell shell = checkout();
      await const RequireGitIdentity(repository).check(contextOn(shell: shell));
      expect(shell.commands.where((Command c) => !c.observes), isEmpty);
    });
  });

  group('push ability is proven before the work, and with a dry run', () {
    const RequirePushableRemote gate = RequirePushableRemote(
      repository: repository,
      remote: remote,
      branch: base,
    );

    test('a remote that answers and would accept a push is satisfied', () async {
      expect(await gate.check(contextOn(shell: checkout())), isA<Satisfied>());
    });

    test('the proof is offered as a push that changes nothing', () async {
      final FakeShell shell = checkout();
      await gate.check(contextOn(shell: shell));

      expect(shell.ran, contains('git -C $repository push --dry-run $remote $base'));
      expect(
        shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a proof that changed the remote would not be a proof, it would be the work',
      );
    });

    test('a remote that would refuse the push is refused here, before anything exists', () async {
      final FakeShell shell = checkout()
        ..fails(
          'git -C $repository push --dry-run $remote $base',
          stderr: 'remote: Permission denied',
        );

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('Permission denied'));
      expect(answer.reason, contains('refuse a push'));
    });

    test('no remote at all is refused as that', () async {
      final FakeShell shell = checkout()..fails('git -C $repository remote get-url $remote');

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains(remote));
      expect(
        shell.ran,
        isNot(contains('git -C $repository push --dry-run $remote $base')),
        reason: 'there is nothing to offer a push to',
      );
    });

    test('an unreachable remote is refused before a push is offered to it', () async {
      final FakeShell shell = checkout()
        ..fails(
          'git -C $repository ls-remote --heads $remote',
          stderr: 'Could not resolve hostname',
        );

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('Could not resolve hostname'));
      expect(shell.ran, isNot(contains('git -C $repository push --dry-run $remote $base')));
    });

    test('the name of the remote is the row\'s, and nothing here assumes one', () async {
      // The step used to have the name written into it in three places, so a checkout whose remote
      // was called anything else was refused for a remote it did have.
      const RequirePushableRemote named = RequirePushableRemote(
        repository: repository,
        remote: 'upstream',
        branch: base,
      );
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository remote get-url upstream', 'git@example.com:example/t.git\n')
        ..answers('git -C $repository ls-remote --heads upstream', 'abc\trefs/heads/$base\n')
        ..answers('git -C $repository push --dry-run upstream $base', '');

      expect(await named.check(contextOn(shell: shell)), isA<Satisfied>());
      expect(shell.ran, contains('git -C $repository push --dry-run upstream $base'));
    });

    test('nothing it runs can stop to ask a question', () async {
      // There is no terminal on the other side of this run, so a prompt does not fail it — it hangs
      // it until the deadline, and a hung run cannot be told from a working one.
      final FakeShell shell = checkout();
      await gate.check(contextOn(shell: shell));

      final Iterable<Command> reaching = shell.commands.where(
        (Command c) => c.arguments.contains('ls-remote') || c.arguments.contains('push'),
      );
      expect(reaching, isNotEmpty);
      for (final Command command in reaching) {
        expect(command.environment['GIT_TERMINAL_PROMPT'], '0');
        expect(command.environment['GIT_SSH_COMMAND'], contains('BatchMode=yes'));
        expect(command.timeout, isNotNull, reason: 'a remote that never answers is not waited for');
      }
    });
  });
}
