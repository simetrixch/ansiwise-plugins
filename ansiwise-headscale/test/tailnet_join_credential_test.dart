import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';
import 'package:test/test.dart';

/// The credential the coordinator mints, and the two failures the step is built around: minting on
/// SILENCE, and minting BESIDE a key the coordinator would still redeem. Each is planted here and
/// observed refused, next to the innocent case that goes through.
void main() {
  /// The step as a program row would state it: the admin surface reached through a workload exec
  /// whose words carry the run's marked slot, the machine's name read from the answer the row
  /// names, and the credential put where the caller said.
  const TailnetJoinCredential step = TailnetJoinCredential(
    invocation: <String>['exec-into', '<stage>', 'headscale'],
    needsRoot: false,
    userAnswer: 'machine',
    ttl: '24h',
    keyFile: '/run/join-key',
    runAnswer: 'stage',
  );

  /// The invocation with this run's stage where the slot marked it.
  const String admin = 'exec-into t1 headscale';

  StepContext contextOn(FakeShell shell, FakeFiles files, [FakeClock? clock]) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: clock ?? FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('tailnet_join_credential'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'machine': 'm1', 'stage': 't1'}),
    facts: Facts.none,
  );

  test('a coordinator that cannot be asked BLOCKS — nothing is minted on silence', () async {
    // The planted defect this guards: concluding "no key, mint one" from a listing that did not
    // answer, which is how a caller logs a machine out on the strength of a credential that turns
    // out not to exist.
    final FakeShell shell = FakeShell()
      ..fails('$admin users list -o json', stderr: 'connection refused');
    final CheckResult answer = await step.check(contextOn(shell, FakeFiles()));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('nothing is minted on silence'));
  });

  test(
    'a machine with no coordinator user is ready, and the apply creates, mints and stages',
    () async {
      // JSON `null`, WHICH IS WHAT A FRESH COORDINATOR REALLY WRITES — measured on apps3
      // (2026-08-29), at exit 0. This case scripted an empty ARRAY, a shape headscale does not
      // emit, so it proved a reading nothing performs while the real one went unread: the run
      // stopped saying the admin surface had not answered, on the very first slave an
      // installation ever adds.
      final FakeShell shell = FakeShell()..answers('$admin users list -o json', 'null');
      shell.changes('$admin users create m1', () {
        shell.answers('$admin users list -o json', '[{"name":"m1","id":7}]');
        shell.answers('$admin preauthkeys list --user 7 -o json', 'null');
      });
      shell.answers(
        '$admin preauthkeys create --user 7 --expiration 24h -o json',
        '{"key":"k-new"}',
      );
      final FakeFiles files = FakeFiles();
      final StepContext context = contextOn(shell, files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(files.contents['/run/join-key'], 'k-new\n');
      expect(shell.ran, contains('$admin users create m1'));
    },
  );

  test('an empty user listing is an ANSWER, and the check is ready on it', () async {
    // The two are told apart by the exit code and by nothing else: `null` at exit 0 is a
    // coordinator saying it has no users, and the case above proves the apply then creates one.
    // Silence is the case before that one — a non-zero exit — and it still blocks.
    final FakeShell shell = FakeShell()..answers('$admin users list -o json', 'null');
    expect(await step.check(contextOn(shell, FakeFiles())), isA<Ready>());
  });

  test('output that is neither a listing nor that empty answer IS silence', () async {
    // A surface answering something else has not answered: minting on it would hand a machine a
    // credential nothing agreed to redeem.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', 'Error: unknown command');
    final CheckResult answer = await step.check(contextOn(shell, FakeFiles()));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('nothing is minted on silence'));
  });

  test('a key the coordinator still redeems is handed back, never replaced', () async {
    // Create-only, proven by absence: the check is satisfied on the standing credential, so a
    // second run reaches no create at all and the coordinator ends the day holding ONE live key.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers('$admin preauthkeys list --user 7 -o json', '[{"key":"k-live","used":false}]');
    final FakeFiles files = FakeFiles(<String, String>{'/run/join-key': 'k-live\n'});

    final CheckResult answer = await step.check(contextOn(shell, files));

    expect(answer, isA<Satisfied>());
    expect(shell.ran.where((String c) => c.contains('create')), isEmpty);
  });

  test(
    'a key the coordinator reports as USED is replaced — a dead key is not a live credential',
    () async {
      final FakeShell shell = FakeShell()
        ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
        ..answers('$admin preauthkeys list --user 7 -o json', '[{"key":"k-spent","used":true}]')
        ..answers(
          '$admin preauthkeys create --user 7 --expiration 24h -o json',
          '{"key":"k-fresh"}',
        );
      final FakeFiles files = FakeFiles(<String, String>{'/run/join-key': 'k-spent\n'});
      final StepContext context = contextOn(shell, files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(files.contents['/run/join-key'], 'k-fresh\n');
    },
  );

  test('an EXPIRED key is replaced, and an expiration that cannot be read keeps the key', () async {
    // Two keys: one past its expiration at the fake clock's 2026 reading, one whose timestamp is
    // unreadable. The expired one may not be reused — handing it back fails the join with an error
    // about the network rather than about the key — and the unreadable one MUST be, because doubt
    // read as "dead" is what makes a run mint a second live credential beside the first.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers(
        '$admin preauthkeys list --user 7 -o json',
        '[{"key":"k-old","used":false,"expiration":"2025-01-01T00:00:00.000001Z"},'
            '{"key":"k-odd","used":false,"expiration":"not-a-moment"}]',
      );
    final FakeFiles files = FakeFiles(<String, String>{'/run/join-key': 'k-odd\n'});

    expect(await step.check(contextOn(shell, files)), isA<Satisfied>());

    files.contents['/run/join-key'] = 'k-old\n';
    expect(await step.check(contextOn(shell, files)), isA<Ready>());
  });

  test('a mint that returns no key fails WITHOUT the output riding the error', () async {
    // The coordinator's answer to a failed create is not a credential, but nothing here may gamble
    // on that: whatever it printed must not reach an exception message, which outlives the run in
    // the record.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers('$admin preauthkeys list --user 7 -o json', 'null')
      ..answers('$admin preauthkeys create --user 7 --expiration 24h -o json', 'k-leaked-anyway');
    await expectLater(
      step.apply(contextOn(shell, FakeFiles())),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          isNot(contains('k-leaked-anyway')),
        ),
      ),
    );
  });

  test(
    'the machine\'s name fills its own slot in the key file, so two credentials never share',
    () async {
      // Two machines minted on one coordinator in the same moment must not race over one path — the
      // slot spelled with the user answer's name is what keeps them apart.
      const TailnetJoinCredential perMachine = TailnetJoinCredential(
        invocation: <String>['exec-into', '<stage>', 'headscale'],
        needsRoot: false,
        userAnswer: 'machine',
        ttl: '24h',
        keyFile: '/run/join-key-<machine>',
        runAnswer: 'stage',
      );
      final FakeShell shell = FakeShell()
        ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
        ..answers('$admin preauthkeys list --user 7 -o json', 'null')
        ..answers('$admin preauthkeys create --user 7 --expiration 24h -o json', '{"key":"k-m1"}');
      final FakeFiles files = FakeFiles();

      await perMachine.apply(contextOn(shell, files));

      expect(files.contents['/run/join-key-m1'], 'k-m1\n');
    },
  );

  test('the credential never rides the command line', () async {
    // The value leaves the step through the file alone. Every command the fake recorded is checked
    // against it, because an argument is visible to every account on the machine.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers('$admin preauthkeys list --user 7 -o json', 'null')
      ..answers(
        '$admin preauthkeys create --user 7 --expiration 24h -o json',
        '{"key":"k-secret"}',
      );
    final FakeFiles files = FakeFiles();

    await step.apply(contextOn(shell, files));

    expect(shell.ran.where((String c) => c.contains('k-secret')), isEmpty);
    expect(files.contents['/run/join-key'], 'k-secret\n');
  });
}

final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
