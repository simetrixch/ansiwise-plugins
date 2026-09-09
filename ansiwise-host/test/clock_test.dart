import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A machine's clock, and the one row that is allowed to move it.
///
/// The readings below are `chronyc tracking` as real machines printed it on 2026-09-09, with the source's own name put back to a placeholder: one out by
/// 69 seconds with its three sources reachable, and one in the same minute with no source at all.
/// Telling those two apart is the whole of what this row decides.
void main() {
  const String trackingOut =
      'Reference ID    : D5EFEFA5 (time1.example.invalid)\n'
      'Stratum         : 3\n'
      'Ref time (UTC)  : Wed Sep 09 06:39:12 2026\n'
      'System time     : 69.246482849 seconds fast of NTP time\n'
      'Last offset     : +0.000011959 seconds\n'
      'Leap status     : Normal\n';
  const String trackingSlow =
      'Reference ID    : D5EFEFA5 (time1.example.invalid)\n'
      'System time     : 4.500000000 seconds slow of NTP time\n';
  const String trackingClose =
      'Reference ID    : D5EFEFA5 (time1.example.invalid)\n'
      'System time     : 0.000004581 seconds fast of NTP time\n';
  const String trackingNoSource =
      'Reference ID    : 00000000 ()\n'
      'Stratum         : 0\n'
      'System time     : 0.000000000 seconds fast of NTP time\n'
      'Leap status     : Not synchronised\n';

  final String tracking = trackingCommand.argv.join(' ');
  final String synchronised = synchronisedCommand.argv.join(' ');
  const String makestep = 'chronyc makestep';
  const ClockInStep step = ClockInStep(toleranceSeconds: 1, timeoutSeconds: 30, intervalSeconds: 5);
  const StepName under = StepName('clock_in_step');

  /// A machine whose tracking reads [reading] and whose kernel answers [says], with the step command
  /// answering and — where [thenSynchronised] — making the kernel agree the way a real step does.
  HostMachine machineWhere(String reading, String says, {bool thenSynchronised = false}) {
    final HostMachine machine = HostMachine();
    machine.shell.answers(tracking, reading);
    machine.shell.answers(synchronised, says);
    machine.shell.answers(makestep, '');
    if (thenSynchronised) {
      machine.shell.changes(makestep, () => machine.shell.answers(synchronised, 'yes\n'));
    }
    return machine;
  }

  group('what the tracking reading says', () {
    test('how far out the clock stands, with the direction kept', () {
      expect(clockOffsetFrom(trackingOut), closeTo(69.246, 0.001));
      expect(clockOffsetFrom(trackingSlow), closeTo(-4.5, 0.001));
      expect(clockOffsetFrom(trackingClose), closeTo(0.0000046, 0.0000001));
    });

    test('a reading without that line is no measurement, and answers nothing rather than zero', () {
      expect(clockOffsetFrom('Stratum : 3\n'), isNull);
    });

    test('the reference nobody has is a machine that reaches no source', () {
      expect(hasReference(trackingOut), isTrue);
      expect(hasReference(trackingNoSource), isFalse);
      expect(hasReference('Stratum : 0\n'), isFalse);
    });
  });

  group('the row', () {
    test('a synchronised kernel is nothing to do, and it says how far off it stands', () async {
      final CheckResult answer = await step.check(
        machineWhere(trackingClose, 'yes\n').contextFor(under),
      );
      expect((answer as Satisfied).because, contains('synchronised'));
    });

    test(
      'a clock with no reading YET is waited for, never refused - the service is seconds old here',
      () async {
        // The row that enables the time service stands directly above this one in the program, so
        // this is what a real machine answers a second later: no reference, every source at reach 0.
        // Refusing it read "not yet" as "never" and stopped a bare machine's first install
        // (ansiwise-plugins#184).
        final CheckResult answer = await step.check(
          machineWhere(trackingNoSource, 'no\n').contextFor(under),
        );
        expect(answer, isA<Ready>());
      },
    );

    test('a source that never appears ends the row, and says that is what was missing', () async {
      final HostMachine machine = machineWhere(trackingNoSource, 'no\n');
      await expectLater(
        () => step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong e) => '$e',
            'names what was never reached',
            allOf(contains('a time source this machine can reach'), contains('reach 0')),
          ),
        ),
      );
      // It never stepped, because there was nothing to step toward.
      expect(machine.changing, isNot(contains(makestep)));
    });

    test('a source that appears LATE is stepped then, not skipped', () async {
      // The counter-probe of the two above, and the case the old shape got wrong twice over: it
      // refused before waiting, and had it waited it would have stepped before any reference existed
      // and then left the machine slewing its whole offset. Here the first `tracking` read answers
      // with no source and that same read starts answering with one, the way a first poll completing
      // does.
      final HostMachine machine = machineWhere(trackingNoSource, 'no\n', thenSynchronised: true);
      machine.shell.changes(tracking, () {
        machine.shell.answers(tracking, trackingOut);
      });
      await step.apply(machine.contextFor(under));
      expect(machine.changing, contains(makestep));
    });

    test('out of step with a source reachable, the row is ready to act', () async {
      final CheckResult answer = await step.check(
        machineWhere(trackingOut, 'no\n').contextFor(under),
      );
      expect(answer, isA<Ready>());
    });

    test('it steps the clock, and then waits for the kernel to agree', () async {
      final HostMachine machine = machineWhere(trackingOut, 'no\n', thenSynchronised: true);
      await step.apply(machine.contextFor(under));
      expect(machine.changing, contains(makestep));
    });

    test('inside the tolerance it waits and does NOT move the clock', () async {
      final HostMachine machine = machineWhere(trackingClose, 'no\n');
      machine.shell.changes('unreachable', () {});
      machine.shell.answers(synchronised, 'yes\n');
      await step.apply(machine.contextFor(under));
      expect(machine.changing, isNot(contains(makestep)));
    });

    test('a kernel that never agrees ends the row, naming how far out it still stands', () async {
      final HostMachine machine = machineWhere(trackingOut, 'no\n');
      await expectLater(
        () => step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong e) => '$e',
            'names the offset',
            contains('69.246'),
          ),
        ),
      );
    });
  });
}
