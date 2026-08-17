import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// The identity a checkout makes its commits as, set by the run rather than by a person.
///
/// **Why this is driven here and not by the idempotence audit.** The step reads both values out of
/// answers whose NAMES its row chooses, and a probe holds no answers at all — so it would be
/// measured against a run that knows nothing, which is not the act this step performs. The property
/// the audit would have measured is measured here instead: applied twice, the second run has nothing
/// to do.
///
/// **What must never happen is the undo taking away somebody else's identity.** A checkout that
/// already had one keeps it, because it is theirs and this run did not create it.
void main() {
  const String nameOf = 'committer_name';
  const String mailboxOf = 'committer_email';
  const GitIdentity step = GitIdentity(
    repository: repository,
    nameAnswer: nameOf,
    emailAnswer: mailboxOf,
  );

  const String wantedName = 'apps1.example.com';
  const String wantedMailbox = 'installer@example.com';

  /// A run holding both answers, against the machine [shell] describes.
  StepContext runOn(FakeShell shell) => StepContext(
    shell: shell,
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{nameOf: wantedName, mailboxOf: wantedMailbox}),
    facts: Facts.none,
  );

  /// A checkout that is one, and whose identity is [name] and [mailbox] — null for none at all.
  FakeShell checkoutHolding({String? name, String? mailbox}) {
    final FakeShell shell = FakeShell()
      ..answers('git -C $repository rev-parse --git-dir', '.git\n');
    if (name == null) {
      shell.fails('git -C $repository config --get user.name');
    } else {
      shell.answers('git -C $repository config --get user.name', '$name\n');
    }
    if (mailbox == null) {
      shell.fails('git -C $repository config --get user.email');
    } else {
      shell.answers('git -C $repository config --get user.email', '$mailbox\n');
    }
    return shell;
  }

  group('a checkout with no identity', () {
    test('there is work to do', () async {
      expect(await step.check(runOn(checkoutHolding())), isA<Ready>());
    });

    test('both settings are written, LOCAL to the checkout and never global', () async {
      final FakeShell shell = checkoutHolding();
      await step.apply(runOn(shell));

      expect(shell.ran, contains('git -C $repository config user.name $wantedName'));
      expect(shell.ran, contains('git -C $repository config user.email $wantedMailbox'));
      expect(
        shell.ran.where((String each) => each.contains('--global')),
        isEmpty,
        reason: 'a machine may hold several checkouts and only one of them is this installation\'s',
      );
    });

    test('and afterwards it is finished, so a second run does nothing', () async {
      final FakeShell shell = checkoutHolding();
      shell.changes('git -C $repository config user.name $wantedName', () {
        shell.answers('git -C $repository config --get user.name', '$wantedName\n');
      });
      shell.changes('git -C $repository config user.email $wantedMailbox', () {
        shell.answers('git -C $repository config --get user.email', '$wantedMailbox\n');
      });
      final StepContext context = runOn(shell);

      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });
  });

  group('a checkout that already carries an identity', () {
    test('one that differs is work, because the run states who commits', () async {
      final FakeShell shell = checkoutHolding(name: 'Somebody Else', mailbox: 'else@example.com');
      expect(await step.check(runOn(shell)), isA<Ready>());
    });

    test('and the undo puts back exactly what stood there, never this run\'s', () async {
      // The property that matters most. An undo runs while cleaning up after a failure, which is the
      // worst moment to take away an identity somebody set for their own reasons.
      final FakeShell shell = checkoutHolding(name: 'Somebody Else', mailbox: 'else@example.com');
      final StepContext context = runOn(shell);

      final GitIdentityBefore held = await step.capture(context);
      await step.apply(context);
      await step.undo(context, held);

      expect(shell.ran, contains('git -C $repository config user.name Somebody Else'));
      expect(shell.ran, contains('git -C $repository config user.email else@example.com'));
    });
  });

  group('a checkout that had NO identity', () {
    test('has the setting TAKEN OUT again, not emptied', () async {
      // An empty value reads as set to git and as unset to everybody else, which is the one state
      // that satisfies neither — so the undo removes the key rather than writing nothing into it.
      final FakeShell shell = checkoutHolding();
      final StepContext context = runOn(shell);

      final GitIdentityBefore held = await step.capture(context);
      await step.apply(context);
      await step.undo(context, held);

      expect(shell.ran, contains('git -C $repository config --unset user.name'));
      expect(shell.ran, contains('git -C $repository config --unset user.email'));
    });
  });

  test('a path that is not a checkout is refused as that, not as a missing identity', () async {
    final FakeShell shell = FakeShell()
      ..fails('git -C $repository rev-parse --git-dir', stderr: 'not a git repository');
    final CheckResult answer = await step.check(runOn(shell));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('no git checkout'));
  });
}
