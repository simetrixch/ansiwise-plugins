import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Bringing a service onto the executable that stands on disk.
///
/// **THE STATE THIS EXISTS FOR IS INVISIBLE FROM THE DISK.** Replacing an executable is a rename: a
/// process that is already running keeps the inode it started from, which is what makes the
/// replacement safe, and it also means the service goes on serving the OLD code while every reading
/// of the file says the new version is there. A machine reports itself at its pin and is not.
///
/// So the question is asked of the KERNEL. `/proc/<pid>/exe` links to the inode a process is
/// executing, and the kernel renders it as `<path> (deleted)` where that inode no longer has a
/// name. No timestamps are compared, which is the alternative and the one that has to reconcile a
/// monotonic clock against a wall clock and answers wrongly the first time either moves.
void main() {
  const StepName under = StepName('under_test');
  const String unit = 'ansiwise.service';
  const String pid = '4242';
  const String binary = '/usr/local/bin/ansiwise-rest';
  const RestartStaleService step = RestartStaleService(unit: unit);

  const String shown = 'systemctl show -p LoadState -p ActiveState -p MainPID $unit';

  /// A machine whose unit is loaded, running, and executing [running].
  HostMachine serving(String running) {
    final HostMachine machine = HostMachine();
    machine.shell
      ..answers(shown, 'LoadState=loaded\nActiveState=active\nMainPID=$pid\n')
      ..answers('readlink /proc/$pid/exe', '$running\n');
    return machine;
  }

  group('what the kernel says about the running process', () {
    test('a service running a replaced executable has work to do', () async {
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a service running the file that is there is left alone', () async {
      final HostMachine machine = serving(binary);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the plan names the unit, and nothing else is restarted', () async {
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains(unit));
    });
  });

  group('the states this step deliberately does not act on', () {
    test('a unit the service manager does not know is REFUSED, naming it', () async {
      // Restarting nothing is not restarting. A row pointing at a unit that is not there is a row
      // that will never do what it says, and passing over it silently is how that survives.
      final HostMachine machine = HostMachine();
      machine.shell.answers(shown, 'LoadState=not-found\nActiveState=inactive\nMainPID=0\n');

      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, allOf(contains(unit), contains('not-found')));
    });

    test('a unit that is loaded and stopped is satisfied, and says why', () async {
      // Something stopped it. A step whose name is about staleness starting it again would be
      // deciding a thing nobody asked it to decide.
      final HostMachine machine = HostMachine();
      machine.shell.answers(shown, 'LoadState=loaded\nActiveState=inactive\nMainPID=0\n');

      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Satisfied>());
      expect((result as Satisfied).because, contains('running no old executable'));
      expect(machine.changing, isEmpty);
    });

    test('an active unit with no main process is refused rather than guessed at', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(shown, 'LoadState=loaded\nActiveState=active\nMainPID=0\n');

      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('names no main process'));
    });

    test('a service manager that will not answer at all is refused', () async {
      final HostMachine machine = HostMachine();
      machine.shell.fails(shown, stderr: 'Failed to connect to bus');
      final CheckResult result = await step.check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('Failed to connect to bus'));
    });
  });

  group('the verdict after the restart', () {
    test('is read off the service manager, so a restart that came back down fails', () async {
      // A restart that returns zero and a service that came back UP are two different facts. A unit
      // whose new executable refuses its own configuration is restarted successfully and is down a
      // second later, and a step reading only the exit code calls that done.
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      machine.shell.changes('systemctl restart $unit', () {
        machine.shell.answers(shown, 'LoadState=loaded\nActiveState=failed\nMainPID=0\n');
      });

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('is not running'),
          ),
        ),
      );
    });

    test('a restart that left the old inode running fails, and says what that means', () async {
      // The unit did not actually stop: a lingering process it does not account for, or a manager
      // configured to keep one. Reported as done, the machine goes on serving what it served.
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      // The restart changes nothing about the link, which is the whole of the case.

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('STILL running a replaced executable'),
          ),
        ),
      );
    });

    test('a restart the manager refused fails as the command it was', () async {
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      machine.shell.fails('systemctl restart $unit', stderr: 'Job for $unit failed');

      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
    });

    test('INNOCENT CASE: a restart that worked leaves the step satisfied', () async {
      final HostMachine machine = serving('$binary ${RestartStaleService.deletedMarker}');
      machine.shell.changes('systemctl restart $unit', () {
        machine.shell.answers('readlink /proc/$pid/exe', '$binary\n');
      });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });
  });

  test('it says what a restart costs, because nothing here keeps a record of it', () {
    expect(step.irreversibleReason, allOf(contains('not resumed'), contains('connection')));
  });
}
