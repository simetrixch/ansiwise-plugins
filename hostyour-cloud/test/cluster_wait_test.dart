import 'dart:async';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// Waiting until a command answers: which answer counts, and what a reached deadline says.
///
/// The three rows of `deploy-cluster` that wait this way — the node coming up, the part of the
/// certificate service that admits certificate objects, and the issuer registering its account —
/// carry their command and their answer in the program file, and the whole program is run against a
/// converged machine in `cluster_program_test.dart`. What is measured here is the mechanism those
/// rows rest on.
void main() {
  const StepName under = StepName('under_test');
  const String issuerReady =
      'microk8s kubectl get clusterissuer letsencrypt-prod -o '
      'jsonpath={.status.conditions[?(@.type=="Ready")].status}';

  WaitForAnswer waitingFor(String answer, {int timeoutSeconds = 60}) => WaitForAnswer(
    waitingFor: 'letsencrypt-prod to report that its account is registered',
    command: 'microk8s',
    commandArguments: const <String>[
      'kubectl',
      'get',
      'clusterissuer',
      'letsencrypt-prod',
      '-o',
      'jsonpath={.status.conditions[?(@.type=="Ready")].status}',
    ],
    answer: answer,
    timeoutSeconds: timeoutSeconds,
    intervalSeconds: 10,
  );

  group('what counts as an answer', () {
    test('the answer is a whole line and never a part of one', () async {
      // The reading that would report a thing as ready because its name appears somewhere in a
      // longer line — in a heading, in a comment beside it, or in a list of what is NOT ready.
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers(issuerReady, 'NotTrue\nTrueish\n');

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Ready>());
    });

    test('surrounding spaces are not part of the answer', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '  True  \n');

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a command that says nothing has not said yes', () async {
      // Something just applied carries no status at all yet, which reads as empty output rather
      // than as a no.
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '');

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Ready>());
    });

    test('a command that failed has not answered, whatever it printed', () async {
      // BOTH have to hold. A zero exit code alone proves nothing — which is why the output decides
      // — but reading a yes out of what a FAILED command happened to print is reporting success
      // over a real failure, and that is the one thing this framework exists to end. All three
      // waits this capability replaced required the exit code.
      //
      // The cost is real and it is the smaller one: a command that fails while printing the answer
      // reaches its deadline, which is recorded and loud. The other way round it becomes a silent
      // yes, and that cannot be repaid once somebody has relied on it.
      final ClusterMachine machine = ClusterMachine()
        ..shell.answer(
          issuerReady,
          const CommandResult(exitCode: 1, stdout: 'True\n', stderr: '', elapsed: Duration.zero),
        );

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Ready>());
    });

    test('it only looks, so a dry run may run it', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, 'True');

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });

  group('the budget', () {
    test('an answer that arrives while it is waiting ends the wait', () async {
      final ClusterMachine machine = ClusterMachine();
      int looks = 0;
      machine.shell
        ..answers(issuerReady, '')
        ..changes(issuerReady, () {
          looks++;
          if (looks >= 3) {
            machine.shell.answers(issuerReady, 'True');
          }
        });

      await waitingFor('True').apply(machine.contextFor(under));

      expect(await waitingFor('True').check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.clock.elapsed.inSeconds, greaterThan(0));
    });

    test('a wait that runs out says what it was waiting for, by name', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '');

      await expectLater(
        waitingFor('True').apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.message,
            'what it says',
            allOf(
              contains('letsencrypt-prod to report that its account is registered'),
              contains('60s'),
            ),
          ),
        ),
      );
      expect(machine.clock.elapsed.inSeconds, greaterThanOrEqualTo(60));
    });

    test('a dry run says what it would wait for instead of waiting for it', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '');

      final StepPlan plan = await waitingFor('True').plan(machine.contextFor(under));

      expect(
        plan.summary,
        contains(
          'would wait up to 60s for letsencrypt-prod to report that its account is '
          'registered',
        ),
      );
      expect(machine.clock.elapsed, Duration.zero);
    });
  });

  group('each poll', () {
    test('carries a deadline derived from the row, above the row\'s own budget', () async {
      // The wait's budget is only checked BETWEEN polls, so the poll's command must carry its own
      // deadline or a command that blocks is never interrupted. It sits ABOVE the row's timeout on
      // purpose: the kill must lose the race against any command that answers within the row's
      // budget, so what the operator reads is the command's own message and never "killed".
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, 'True');

      await waitingFor('True', timeoutSeconds: 300).check(machine.contextFor(under));

      final Command poll = machine.shell.commands.single;
      expect(poll.timeout, const Duration(seconds: 330));
      expect(poll.timeout, greaterThan(const Duration(seconds: 300)));
    });

    test('a command that never returns ends the wait instead of hanging it', () async {
      // The shell kills a command at its deadline and throws — proven against real processes in
      // the framework's own tests. What is measured here is the step's side: the failure comes
      // through instead of being read as a quiet no, so the run ends loud with the command named.
      await expectLater(
        waitingFor('True').apply(_contextWith(_WedgedShell(), under)),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('its answer rests on the row\'s word', () {
      // The row chose the command, so the framework cannot verify that it only looks. The step
      // says so, and the engine records every such row as declared rather than proven.
      expect(waitingFor('True').answersOnTrust, isTrue);
    });
  });

  group('what the program hands it', () {
    test('a row that names no arguments asks the bare command', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers('microk8s', 'anything\n');

      const WaitForAnswer bare = WaitForAnswer(
        waitingFor: 'the command to answer at all',
        command: 'microk8s',
        commandArguments: <String>[],
        answer: 'anything',
        timeoutSeconds: 10,
        intervalSeconds: 1,
      );

      expect(await bare.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('every argument the program writes is read by the step', () {
      final WaitForAnswer built = WaitForAnswer.fromArguments(
        const Arguments(<String, Object>{
          'waiting_for': 'the node to report that it is running',
          'command': 'microk8s',
          'command_arguments': <String>['status'],
          'answer': microk8sRunningLine,
          'timeout_seconds': 300,
          'interval_seconds': 5,
        }),
      );

      expect(built.waitingFor, 'the node to report that it is running');
      expect(built.command, 'microk8s');
      expect(built.commandArguments, <String>['status']);
      expect(built.answer, microk8sRunningLine);
      expect(built.deadline, const Duration(seconds: 300));
      expect(built.interval, const Duration(seconds: 5));
    });
  });
}

/// A context whose shell is [shell], for the one test that needs a shell no fake table can be.
StepContext _contextWith(Shell shell, StepName step) => StepContext(
  shell: shell,
  files: FakeFiles(),
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: const _SilentLog(),
  step: step,
  arguments: Arguments.none,
  answers: Arguments.none,
  facts: Facts.none,
);

/// A shell whose command never returns, answered the way the real shell answers it: killed at the
/// command's deadline, and thrown rather than dressed up as a result.
final class _WedgedShell implements Shell {
  @override
  Future<CommandResult> run(Command command) async {
    final Duration? timeout = command.timeout;
    if (timeout == null) {
      // The planted case this probe exists for: without a per-poll deadline the call would simply
      // never complete, and the test would hang the way the run used to.
      return Completer<CommandResult>().future;
    }
    throw TimeoutException('${command.argv.join(' ')} did not finish and was killed', timeout);
  }
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
