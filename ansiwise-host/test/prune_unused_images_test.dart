import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

void main() {
  StepContext contextOn({FakeShell? shell}) => StepContext(
    shell: shell ?? FakeShell(),
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    facts: Facts.none,
  );

  const List<String> prune = <String>['runtime', 'images', 'prune', '--all'];
  const PruneUnusedImages step = PruneUnusedImages(
    path: '/',
    freeKibibytes: 40000000,
    pruneCommand: prune,
    elevated: true,
  );

  FakeShell machine({required int availableKibibytes, bool runtime = true}) {
    final FakeShell shell = FakeShell()
      ..answers(
        'df -Pk /',
        'Filesystem     1024-blocks     Used Available Capacity Mounted on\n'
            '/dev/sda1        128849018 93000000 $availableKibibytes      76% /\n',
      );
    if (runtime) shell.answers(onThePathKey('runtime'), '/usr/bin/runtime\n');
    return shell;
  }

  group('a machine at or above the floor is left alone', () {
    test('one KiB above the floor is satisfied, and nothing is pruned', () async {
      final FakeShell shell = machine(availableKibibytes: 40000001);
      final CheckResult answer = await step.check(contextOn(shell: shell));
      expect((answer as Satisfied).because, contains('40000001 KiB'));
      expect(shell.ran, isNot(contains(prune.join(' '))));
    });

    test('exactly at the floor is satisfied', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: machine(availableKibibytes: 40000000)),
      );
      expect(answer, isA<Satisfied>());
    });
  });

  group('a machine below the floor', () {
    test('is ready to prune where the runtime is installed', () async {
      final CheckResult answer = await step.check(
        contextOn(shell: machine(availableKibibytes: 29783032)),
      );
      expect(answer, isA<Ready>());
    });

    test(
      'is satisfied where the prune command is not on the path, because nothing was pulled yet',
      () async {
        final CheckResult answer = await step.check(
          contextOn(shell: machine(availableKibibytes: 29783032, runtime: false)),
        );
        expect((answer as Satisfied).because, contains('runtime'));
      },
    );

    test('plans the prune command the row names, elevated', () async {
      final StepPlan plan = await step.plan(
        contextOn(shell: machine(availableKibibytes: 29783032)),
      );
      expect((plan as ArgvPlan).argv, prune);
    });

    test('runs the prune command elevated', () async {
      final FakeShell shell = machine(availableKibibytes: 29783032);
      await step.apply(contextOn(shell: shell));
      final Command ran = shell.commands.singleWhere((Command c) => c.executable == 'runtime');
      expect(<String>[ran.executable, ...ran.arguments], prune);
      expect(ran.elevated, isTrue);
    });

    test('a failing prune is an error naming its command and what it printed', () async {
      final FakeShell shell = machine(availableKibibytes: 29783032)
        ..fails(prune.join(' '), stderr: 'ctr: failed to dial');
      expect(
        () => step.apply(contextOn(shell: shell)),
        throwsA(
          isA<CommandFailed>().having(
            (CommandFailed f) => f.toString(),
            'message',
            contains('failed to dial'),
          ),
        ),
      );
    });
  });

  test('a disk it cannot measure is refused rather than pruned', () async {
    final CheckResult answer = await step.check(
      contextOn(shell: FakeShell()..answers('df -Pk /', 'nothing useful\n')),
    );
    expect(answer, isA<Blocked>());
  });

  test('the row states its floor and its command, and the floor is the free-disk check\'s', () {
    final PruneUnusedImages built = PruneUnusedImages.fromArguments(
      const Arguments(<String, Object>{
        'path': '/',
        'free_kibibytes': 40000000,
        'prune_command': prune,
        'elevated': true,
      }),
    );
    expect(
      <Object>[built.path, built.freeKibibytes, built.pruneCommand, built.elevated],
      <Object>['/', 40000000, prune, true],
    );
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
