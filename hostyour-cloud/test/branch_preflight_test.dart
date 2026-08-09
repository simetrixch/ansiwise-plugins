import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// What has to be true before one line of an installation branch is written.
///
/// Every one of these refusals exists because the run used to get all the way to the end and fail
/// there: no committer identity discovered at the commit, no write access discovered at the push,
/// the trunk discovered to be checked out after the first file had been rewritten.
void main() {
  const String repository = '/srv/hostyour-cloud';
  const String fqdn = 'm1.example.com';
  const String trunk = 'master';

  StepContext contextOn({FakeShell? shell, FakeFiles? files, String domain = fqdn}) => StepContext(
    shell: shell ?? FakeShell(),
    files: files ?? FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    // The domain is an ANSWER: nobody can write one into a file that ships to every installation,
    // so it varies per case here rather than per step instance.
    answers: Arguments(<String, Object>{'fqdn': domain}),
    facts: Facts.none,
  );

  /// A checkout that answers every question this preflight asks, the way a healthy one would.
  FakeShell checkout({String head = trunk, String status = '', bool branchExists = false}) {
    final FakeShell shell = FakeShell()
      ..answers('git -C $repository rev-parse --git-dir', '.git\n')
      ..answers('git -C $repository config --get user.name', 'Example Operator\n')
      ..answers('git -C $repository config --get user.email', 'operator@example.com\n')
      ..answers('git -C $repository remote get-url origin', 'git@example.com:example/cloud.git\n')
      ..answers('git -C $repository ls-remote --heads origin', 'abc\trefs/heads/master\n')
      ..answers('git -C $repository push --dry-run origin $trunk', '')
      ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$head\n')
      ..answers('git -C $repository status --porcelain', status);
    if (branchExists) {
      shell.answers('git -C $repository rev-parse --verify --quiet refs/heads/$fqdn', 'abc\n');
    } else {
      shell.fails('git -C $repository rev-parse --verify --quiet refs/heads/$fqdn');
    }
    return shell;
  }

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
    const RequirePushableOrigin gate = RequirePushableOrigin(repository: repository, trunk: trunk);

    test('a remote that answers and would accept a push is satisfied', () async {
      expect(await gate.check(contextOn(shell: checkout())), isA<Satisfied>());
    });

    test('the proof is offered as a push that changes nothing', () async {
      final FakeShell shell = checkout();
      await gate.check(contextOn(shell: shell));

      expect(shell.ran, contains('git -C $repository push --dry-run origin $trunk'));
      expect(
        shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a proof that changed the remote would not be a proof, it would be the work',
      );
    });

    test('a remote that would refuse the push is refused here, before anything exists', () async {
      final FakeShell shell = checkout()
        ..fails(
          'git -C $repository push --dry-run origin $trunk',
          stderr: 'remote: Permission denied',
        );

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('Permission denied'));
      expect(answer.reason, contains('refuse a push'));
    });

    test('no remote at all is refused as that', () async {
      final FakeShell shell = checkout()..fails('git -C $repository remote get-url origin');

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('origin'));
      expect(
        shell.ran,
        isNot(contains('git -C $repository push --dry-run origin $trunk')),
        reason: 'there is nothing to offer a push to',
      );
    });

    test('an unreachable remote is refused before a push is offered to it', () async {
      final FakeShell shell = checkout()
        ..fails(
          'git -C $repository ls-remote --heads origin',
          stderr: 'Could not resolve hostname',
        );

      final CheckResult answer = await gate.check(contextOn(shell: shell));
      expect((answer as Blocked).reason, contains('Could not resolve hostname'));
      expect(shell.ran, isNot(contains('git -C $repository push --dry-run origin $trunk')));
    });

    test('nothing it runs can stop to ask a question', () async {
      // There is no terminal on the other side of this run, so a prompt does not fail it — it hangs
      // it until the deadline, and a hung run cannot be told from a working one.
      final FakeShell shell = checkout();
      await gate.check(contextOn(shell: shell));

      final Iterable<Command> remote = shell.commands.where(
        (Command c) => c.arguments.contains('ls-remote') || c.arguments.contains('push'),
      );
      expect(remote, isNotEmpty);
      for (final Command command in remote) {
        expect(command.environment['GIT_TERMINAL_PROMPT'], '0');
        expect(command.environment['GIT_SSH_COMMAND'], contains('BatchMode=yes'));
        expect(command.timeout, isNotNull, reason: 'a remote that never answers is not waited for');
      }
    });
  });

  group('the branch is cut before anything is stamped', () {
    const CreateInstallBranch step = CreateInstallBranch(repository: repository, trunk: trunk);

    test('from the trunk, with a clean tree, there is work to do', () async {
      expect(await step.check(contextOn(shell: checkout())), isA<Ready>());
    });

    test('the branch is what apply produces, and the check afterwards proves it', () async {
      final FakeShell shell = checkout();
      shell.changes('git -C $repository checkout -b $fqdn', () {
        shell.answers('git -C $repository rev-parse --abbrev-ref HEAD', '$fqdn\n');
      });
      final StepContext context = contextOn(shell: shell);

      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run on the branch does nothing at all', () async {
      final FakeShell shell = checkout(head: fqdn);
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect(answer, isA<Satisfied>());
      expect(shell.ran, isNot(contains('git -C $repository checkout -b $fqdn')));
    });

    test('a branch that already exists is reported, never reset', () async {
      final FakeShell shell = checkout(branchExists: true);
      final CheckResult answer = await step.check(contextOn(shell: shell));

      expect((answer as Blocked).reason, contains('already exists'));
      expect(shell.commands.where((Command c) => !c.observes), isEmpty);
    });

    test('a dirty tree is refused, because the branch would carry it', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: checkout(status: ' M platform/values-dev.yaml\n')),
      );
      expect((answer as Blocked).reason, contains('platform/values-dev.yaml'));
    });

    test('a branch that is neither the trunk nor this installation is refused', () async {
      final CheckResult answer = await step.check(contextOn(shell: checkout(head: 'other-work')));
      expect((answer as Blocked).reason, contains('other-work'));
    });

    test('the placeholder is not an answer, and cannot become an installation', () async {
      // The value the trunk carries for a domain reads as unset wherever it is met, so a branch
      // named after it would be indistinguishable from a tree nobody stamped.
      final CheckResult answer = await step.check(
        contextOn(shell: checkout(), domain: 'example.invalid'),
      );
      expect((answer as Blocked).reason, contains('example.invalid'));
    });

    test('a label with an underscore is refused before the branch exists', () async {
      // git would take it as a branch name and no resolver would ever take it as a host, so the
      // typo used to survive as far as the first failed lookup.
      final FakeShell shell = checkout();
      final CheckResult answer = await step.check(
        contextOn(shell: shell, domain: 'm1_test.example.com'),
      );

      expect((answer as Blocked).reason, contains('not a domain name'));
      expect(shell.ran, isEmpty, reason: 'a value this wrong is refused without asking a machine');
    });

    test('one label is a machine name and not a domain', () async {
      expect(await step.check(contextOn(shell: checkout(), domain: 'm1')), isA<Blocked>());
    });

    test('taking it back returns to the trunk and removes the branch', () async {
      final FakeShell shell = checkout(head: fqdn);
      await step.undo(contextOn(shell: shell));

      expect(shell.ran, contains('git -C $repository checkout $trunk'));
      expect(shell.ran, contains('git -C $repository branch -D $fqdn'));
    });

    test('taking it back leaves a branch this step did not produce alone', () async {
      final FakeShell shell = checkout(head: 'other-work');
      await step.undo(contextOn(shell: shell));

      expect(shell.ran, isNot(contains('git -C $repository branch -D $fqdn')));
    });
  });
}

final class _SilentLog implements StepLog {
  const _SilentLog();

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}
