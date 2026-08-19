import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';
import 'package:test/test.dart';

/// Taking a machine's membership away at the coordinator, and the two failures the step is built
/// around: reporting a removal on SILENCE, and destroying a user that still owns nodes. Each is
/// planted here and observed refused, next to the innocent case that goes through.
void main() {
  /// The step as a program row would state it: the admin surface reached through a workload exec
  /// whose words carry the run's marked slot, the machine's name read from the answer the row
  /// names.
  const RemoveTailnetUser step = RemoveTailnetUser(
    invocation: <String>['exec-into', '<stage>', 'headscale'],
    needsRoot: false,
    userAnswer: 'machine',
    runAnswer: 'stage',
  );

  /// The invocation with this run's stage where the slot marked it.
  const String admin = 'exec-into t1 headscale';

  StepContext contextOn(FakeShell shell) => StepContext(
    shell: shell,
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('remove_tailnet_user'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'machine': 'm1', 'stage': 't1'}),
    facts: Facts.none,
  );

  test(
    'a coordinator that cannot be asked BLOCKS — absence is never concluded from silence',
    () async {
      // The planted defect this guards: a removal reported done while the coordinator was merely
      // unreachable, after which the caller destroys the surfaces a second attempt would need.
      final FakeShell shell = FakeShell()
        ..fails('$admin users list -o json', stderr: 'connection refused');
      final CheckResult answer = await step.check(contextOn(shell));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('nothing is concluded from silence'));
    },
  );

  test('a machine the coordinator does not hold is already removed — nothing to do', () async {
    final FakeShell shell = FakeShell()..answers('$admin users list -o json', '[]');
    expect(await step.check(contextOn(shell)), isA<Satisfied>());
  });

  test('nodes are deleted before the user, and the user goes by its id', () async {
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers(
        '$admin nodes list --user 7 -o json',
        '[{"id":3,"name":"m1"},{"id":5,"name":"m1-b"}]',
      );

    final StepContext context = contextOn(shell);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    final List<String> destructive = shell.ran
        .where((String c) => c.contains('delete') || c.contains('destroy'))
        .toList();
    expect(destructive, <String>[
      '$admin nodes delete --identifier 3 --force',
      '$admin nodes delete --identifier 5 --force',
      '$admin users destroy --identifier 7 --force',
    ]);
  });

  test('a node listing that did not answer stops the removal with NOTHING destroyed', () async {
    // The order of the two refusals is the safety: a run that stops here is repaired by running it
    // again, while one that had already destroyed the user could not be.
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..fails('$admin nodes list --user 7 -o json', stderr: 'connection refused');

    await expectLater(step.apply(contextOn(shell)), throwsA(isA<StateError>()));

    expect(shell.ran.where((String c) => c.contains('destroy')), isEmpty);
    expect(shell.ran.where((String c) => c.contains('delete')), isEmpty);
  });

  test('a node delete the coordinator refuses stops the run before the user is touched', () async {
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers('$admin nodes list --user 7 -o json', '[{"id":3,"name":"m1"}]')
      ..fails('$admin nodes delete --identifier 3 --force', stderr: 'still online');

    await expectLater(step.apply(contextOn(shell)), throwsA(isA<CommandFailed>()));

    expect(shell.ran.where((String c) => c.contains('destroy')), isEmpty);
  });

  test('a machine with no nodes still has its user destroyed — the keys go with it', () async {
    final FakeShell shell = FakeShell()
      ..answers('$admin users list -o json', '[{"name":"m1","id":7}]')
      ..answers('$admin nodes list --user 7 -o json', 'null');

    await step.apply(contextOn(shell));

    expect(shell.ran, contains('$admin users destroy --identifier 7 --force'));
    expect(shell.ran.where((String c) => c.contains('nodes delete')), isEmpty);
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
