import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Taking the distribution's automatic upgrades off a machine, once a run already under way has
/// finished on its own.
void main() {
  const StepName under = StepName('under_test');

  const List<String> timers = <String>['apt-daily.timer', 'apt-daily-upgrade.timer'];
  const List<String> services = <String>['apt-daily.service', 'apt-daily-upgrade.service'];
  const MaskAutomaticUpgrades step = MaskAutomaticUpgrades(
    timers: timers,
    services: services,
    timeoutSeconds: 30,
    intervalSeconds: 5,
  );

  /// The line the manager is asked about [unit], composed from the step's own list.
  String askedAbout(String unit) => <String>[
    'systemctl',
    'show',
    for (final String property in MaskAutomaticUpgrades.properties) ...<String>['-p', property],
    unit,
  ].join(' ');

  /// What the manager answers about one unit.
  String saying({String load = 'loaded', String file = 'enabled', String active = 'inactive'}) =>
      'LoadState=$load\nUnitFileState=$file\nActiveState=$active\n';

  /// A machine whose timers stand as [timer] says and whose services stand as [service] says.
  HostMachine machineWith({required String timer, required String service}) {
    final HostMachine machine = HostMachine();
    for (final String unit in timers) {
      machine.shell.answers(askedAbout(unit), timer);
    }
    for (final String unit in services) {
      machine.shell.answers(askedAbout(unit), service);
    }
    return machine;
  }

  /// The commands that mask, in the order the step issues them.
  List<String> masking() => <String>[
    for (final String unit in timers) 'systemctl mask --now $unit',
  ];

  group('what counts as done', () {
    test('both timers masked and no upgrade running is nothing to do', () async {
      final HostMachine machine = machineWith(
        timer: saying(load: 'masked', file: 'masked'),
        service: saying(),
      );
      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test(
      'a timer merely disabled is not done: the next upgrade package enables it again',
      () async {
        final HostMachine machine = machineWith(
          timer: saying(file: 'disabled'),
          service: saying(),
        );

        expect(await step.check(machine.contextFor(under)), isA<Ready>());
      },
    );

    test('masked timers with an upgrade still running is not done either', () async {
      // The whole reason the wait exists: masking a timer stops nothing it already started.
      final HostMachine machine = machineWith(
        timer: saying(load: 'masked', file: 'masked'),
        service: saying(active: 'activating'),
      );

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a manager that will not answer blocks rather than passes', () async {
      final HostMachine machine = machineWith(timer: saying(), service: saying());
      machine.shell.fails(askedAbout(timers.first), stderr: 'Failed to connect to bus');

      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(timers.first));
    });
  });

  group('masking', () {
    test('masks each timer now, elevated, and reads the manager back', () async {
      final HostMachine machine = machineWith(timer: saying(), service: saying());
      for (final String unit in timers) {
        machine.shell.changes('systemctl mask --now $unit', () {
          machine.shell.answers(askedAbout(unit), saying(load: 'masked', file: 'masked'));
        });
      }

      await step.apply(machine.contextFor(under));

      expect(machine.changing, masking());
      for (final Command command in machine.shell.commands) {
        if (!command.observes) {
          expect(command.elevated, isTrue, reason: '${command.argv} has to run as root');
        }
      }
      expect(machine.clock.slept, isEmpty);
    });

    test('a mask the manager does not confirm is a failure, not a success', () async {
      // The commands exit zero and the manager still calls the timer enabled: that is a unit loaded
      // from a place a mask does not cover, and the exit code must not paper over it.
      final HostMachine machine = machineWith(timer: saying(), service: saying());

      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<StateError>()));
    });
  });

  group('an upgrade already running', () {
    test('is waited out, and only then are the timers masked', () async {
      final HostMachine machine = machineWith(
        timer: saying(),
        service: saying(active: 'activating'),
      );
      // The service finishes on the third look; nothing this step does ends it.
      int looked = 0;
      machine.shell.changes(askedAbout(services.last), () {
        looked += 1;
        if (looked >= 3) {
          machine.shell.answers(askedAbout(services.last), saying());
        }
      });
      machine.shell.changes(askedAbout(services.first), () {
        if (looked >= 2) {
          machine.shell.answers(askedAbout(services.first), saying());
        }
      });
      for (final String unit in timers) {
        machine.shell.changes('systemctl mask --now $unit', () {
          machine.shell.answers(askedAbout(unit), saying(load: 'masked', file: 'masked'));
        });
      }

      await step.apply(machine.contextFor(under));

      expect(machine.clock.slept, hasLength(2));
      expect(machine.changing, masking());
      expect(machine.said.where((String line) => line.contains('waited out')), hasLength(2));
    });

    test('is never stopped or killed by this step', () async {
      final HostMachine machine = machineWith(
        timer: saying(),
        service: saying(active: 'activating'),
      );

      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<WaitedTooLong>()));

      expect(
        machine.changing.where((String line) => line.contains('stop') || line.contains('kill')),
        isEmpty,
      );
      expect(machine.changing, isEmpty);
    });

    test('that outlasts the deadline names the service still running', () async {
      final HostMachine machine = machineWith(
        timer: saying(),
        service: saying(active: 'activating'),
      );

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.waitingFor,
            'waitingFor',
            contains(services.first),
          ),
        ),
      );
      expect(machine.clock.elapsed, greaterThanOrEqualTo(const Duration(seconds: 30)));
    });
  });

  group('taking it back', () {
    test('unmasks and starts only the timers this run masked', () async {
      final HostMachine machine = machineWith(timer: saying(), service: saying());
      machine.shell.answers(askedAbout(timers.first), saying(load: 'masked', file: 'masked'));

      final List<String> captured = await step.capture(machine.contextFor(under));
      expect(captured, <String>[timers.first]);

      await step.undo(machine.contextFor(under), captured);

      expect(machine.changing, <String>[
        'systemctl unmask ${timers.last}',
        'systemctl start ${timers.last}',
      ]);
    });

    test('capture changes nothing', () async {
      final HostMachine machine = machineWith(timer: saying(), service: saying());

      await step.capture(machine.contextFor(under));

      expect(machine.changing, isEmpty);
    });
  });

  group('the row', () {
    test('needs nothing stated: the units and the deadline carry defaults', () {
      final MaskAutomaticUpgrades read = MaskAutomaticUpgrades.fromArguments(
        Arguments.none.withDefaults(<String, Object>{
          for (final ArgumentSpec spec in MaskAutomaticUpgrades.arguments)
            spec.name: spec.defaultValue!,
        }),
      );

      expect(read.timers, timers);
      expect(read.services, services);
      expect(read.timeoutSeconds, 1200);
      expect(read.intervalSeconds, 5);
    });
  });
}
