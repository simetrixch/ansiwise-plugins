import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// What has to be true about a checkout before anything is written into it.
///
/// The refusal exists because without it a run gets all the way to the end and fails there: no
/// write access discovered at the push.
void main() {
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
      // A name written into the step rather than taken from the row refuses a checkout whose remote
      // is called anything else, for a remote it does have.
      const RequirePushableRemote named = RequirePushableRemote(
        repository: repository,
        remote: 'upstream',
        branch: base,
      );
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository remote get-url upstream', 'git@example.com:example/t.git\n')
        ..answers('git -C $repository ls-remote --heads upstream', 'abc\trefs/heads/$base\n')
        ..answers(
          'git -C $repository for-each-ref --format=%(refname) refs/heads/$base',
          'refs/heads/$base\n',
        )
        ..answers('git -C $repository push --dry-run upstream $base', '');

      expect(await named.check(contextOn(shell: shell)), isA<Satisfied>());
      expect(shell.ran, contains('git -C $repository push --dry-run upstream $base'));
    });

    test('the branch may be read out of an answer, for a branch named per installation', () async {
      const RequirePushableRemote perInstallation = RequirePushableRemote(
        repository: repository,
        remote: remote,
        branchAnswer: nameAnswer,
      );
      final FakeShell shell = checkout(branchExists: true)
        ..answers('git -C $repository push --dry-run $remote $branch', '');

      expect(await perInstallation.check(contextOn(shell: shell)), isA<Satisfied>());
      expect(shell.ran, contains('git -C $repository push --dry-run $remote $branch'));
    });

    test('a run holding no answer under that name is refused by the name', () async {
      const RequirePushableRemote perInstallation = RequirePushableRemote(
        repository: repository,
        remote: remote,
        branchAnswer: nameAnswer,
      );
      final FakeShell shell = checkout();

      final CheckResult answer = await perInstallation.check(contextOn(shell: shell, name: null));
      expect((answer as Blocked).reason, contains(nameAnswer));
      expect(
        shell.ran.where((String c) => c.contains('push')),
        isEmpty,
        reason: 'there is no branch to offer a push of',
      );
    });

    test('a row writing a branch AND naming an answer is refused as the pair it is', () async {
      const RequirePushableRemote both = RequirePushableRemote(
        repository: repository,
        remote: remote,
        branch: base,
        branchAnswer: nameAnswer,
      );

      final CheckResult answer = await both.check(contextOn(shell: checkout()));
      expect((answer as Blocked).reason, contains('disagree'));
    });

    test('a row naming neither is refused as that', () async {
      const RequirePushableRemote neither = RequirePushableRemote(
        repository: repository,
        remote: remote,
      );

      final CheckResult answer = await neither.check(contextOn(shell: checkout()));
      expect((answer as Blocked).reason, contains('no branch at all'));
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

  group('a branch this run has not cut yet', () {
    // A test or dry run of the program that cuts the branch: the rows that cut it did not run, so
    // the checkout does not hold it when this gate is asked.
    const RequirePushableRemote perInstallation = RequirePushableRemote(
      repository: repository,
      remote: remote,
      branchAnswer: nameAnswer,
    );

    /// A checkout without the branch, which answers the push this step offered before the way git
    /// answers it.
    FakeShell uncut() => checkout()
      ..fails(
        'git -C $repository push --dry-run $remote $branch',
        stderr:
            'error: src refspec $branch does not match any\n'
            "error: failed to push some refs to 'git@example.com:example/tree.git'",
      );

    test('is proven with HEAD under its name, and the record carries no failed push', () async {
      final FakeShell shell = uncut();
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());

      expect(
        await perInstallation.check(contextOn(shell: recording(shell, recorder))),
        isA<Satisfied>(),
      );
      expect(
        shell.ran,
        contains('git -C $repository push --dry-run $remote HEAD:refs/heads/$branch'),
      );
      expect(recorder.output.where((String line) => line.contains('src refspec')), isEmpty);
      expect(
        recorder.only<CommandFinished>().where((CommandFinished c) => c.exitCode != 0),
        isEmpty,
      );
    });

    test(
      'THE INNOCENT NEIGHBOUR: a branch the checkout holds is offered by its own name',
      () async {
        // Without this, a step that always offered HEAD would pass the case above, and a real run
        // would prove a push of whatever HEAD is instead of the branch the run produced.
        final FakeShell shell = checkout(branchExists: true);

        expect(await perInstallation.check(contextOn(shell: shell)), isA<Satisfied>());
        expect(shell.ran, contains('git -C $repository push --dry-run $remote $branch'));
        expect(shell.ran.where((String c) => c.contains('HEAD:')), isEmpty);
      },
    );

    test('a credential that may not write is still refused, and the record keeps why', () async {
      final FakeShell shell = uncut()
        ..fails(
          'git -C $repository push --dry-run $remote HEAD:refs/heads/$branch',
          stderr: 'remote: Permission denied',
        );
      final MemoryRecorder recorder = MemoryRecorder(FakeClock());

      final CheckResult answer = await perInstallation.check(
        contextOn(shell: recording(shell, recorder)),
      );
      expect((answer as Blocked).reason, contains('Permission denied'));
      // The other half of the first case: a refusal is a failed command and its output IS kept, so
      // the clean record there means nothing failed rather than nothing was kept.
      expect(recorder.output, contains('remote: Permission denied'));
    });

    test('a remote that moved ahead of the branch the checkout holds is still refused', () async {
      final FakeShell shell = checkout(branchExists: true)
        ..fails(
          'git -C $repository push --dry-run $remote $branch',
          stderr: ' ! [rejected]        $branch -> $branch (fetch first)',
        );

      final CheckResult answer = await perInstallation.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('fetch first'));
      expect(answer.reason, contains('moved ahead'));
    });
  });
}
