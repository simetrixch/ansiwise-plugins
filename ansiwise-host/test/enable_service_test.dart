import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Handing a unit file to the service manager, so the service runs now and again at every boot.
void main() {
  const StepName under = StepName('under_test');

  // What a product's program row would state. The step carries no default for it — which unit a
  // machine is to run is the product's own.
  const String unit = 'unseal.service';
  const EnableService step = EnableService(unit: unit);

  /// The line the manager is asked, composed from the step's own list rather than written out — a
  /// property added there is one these tests arrange for, instead of a fake that quietly stops
  /// matching the command and answers nothing to every question.
  final String asked = <String>[
    'systemctl',
    'show',
    for (final String property in EnableService.properties) ...<String>['-p', property],
    unit,
  ].join(' ');

  /// What the manager answers, property by property.
  String saying({
    String load = 'loaded',
    String file = 'enabled',
    String active = 'active',
    String reload = 'no',
  }) => 'LoadState=$load\nUnitFileState=$file\nActiveState=$active\nNeedDaemonReload=$reload\n';

  /// A machine whose manager answers [state] about the unit.
  HostMachine machineSaying(String state) {
    final HostMachine machine = HostMachine();
    machine.shell.answers(asked, state);
    return machine;
  }

  group('what counts as done', () {
    test('enabled, running, and read from the disk as it stands is nothing to do', () async {
      final HostMachine machine = machineSaying(saying());
      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains(unit));
      expect(machine.changing, isEmpty);
    });

    test('a unit nothing starts at boot is not done, however healthy it looks now', () async {
      // The whole point of the step. A service that is running and is not wanted by the target the
      // manager reaches on its way up is gone at the next restart, and every other question about
      // it answers that it is fine.
      final HostMachine machine = machineSaying(saying(file: 'disabled'));
      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a unit the manager loaded before the file was rewritten is not done', () async {
      // The manager answers this itself. Nothing here compares a file's modification time against a
      // service's start time, which are two clocks.
      final HostMachine machine = machineSaying(saying(reload: 'yes'));
      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a unit that failed is not done', () async {
      final HostMachine machine = machineSaying(saying(active: 'failed'));
      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a manager that will not answer BLOCKS, and never reports the unit as fine', () async {
      // The two answers look alike from outside and are opposites. A machine whose manager cannot
      // be asked is one nothing knows anything about, and reporting that as satisfied would leave
      // an installation believing a service is installed that may not exist at all.
      final HostMachine machine = HostMachine();
      machine.shell.fails(asked);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(unit));
    });
  });

  group('handing the unit over', () {
    /// A machine whose manager behaves the way a real one does: each command takes one of the three
    /// things that are not yet true away.
    HostMachine arriving({required String file, required String active, required String reload}) {
      final HostMachine machine = HostMachine();
      final Map<String, String> state = <String, String>{
        'file': file,
        'active': active,
        'reload': reload,
      };
      void answer() => machine.shell.answers(
        asked,
        saying(file: state['file']!, active: state['active']!, reload: state['reload']!),
      );

      answer();
      machine.shell
        ..changes('systemctl daemon-reload', () {
          state['reload'] = 'no';
          answer();
        })
        ..changes('systemctl enable $unit', () {
          state['file'] = 'enabled';
          answer();
        })
        ..changes('systemctl restart $unit', () {
          state['active'] = 'active';
          answer();
        });
      return machine;
    }

    test('the manager is told to read the directory before it is asked to enable', () async {
      // A unit file an earlier row of the same run wrote is a file the manager has not seen, and
      // enabling a unit it does not know is a command about nothing.
      final HostMachine machine = arriving(file: 'disabled', active: 'inactive', reload: 'yes');
      await step.apply(machine.contextFor(under));

      expect(machine.changing, <String>[
        'systemctl daemon-reload',
        'systemctl enable $unit',
        'systemctl restart $unit',
      ]);
    });

    test('a second run finds nothing to do, so no command runs again', () async {
      final HostMachine machine = arriving(file: 'disabled', active: 'inactive', reload: 'yes');
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final int ran = machine.changing.length;

      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'a check that is satisfied is never followed by an apply',
      );
      expect(machine.changing, hasLength(ran));
    });

    test('a unit already enabled and running is RESTARTED, never left as it stands', () async {
      // A rewritten unit file leaves the manager holding a command line that has never been
      // executed. `start` on a unit reporting itself as having succeeded does nothing at all, so
      // the proof that this file works would first be attempted at a restart nobody watches.
      final HostMachine machine = arriving(file: 'enabled', active: 'active', reload: 'yes');
      await step.apply(machine.contextFor(under));

      expect(machine.changing, contains('systemctl restart $unit'));
    });

    test('a unit that comes back not running FAILS, naming what the manager said', () async {
      // The verdict is read off the manager and never off the exit code of the enabling. A restart
      // that returns zero and a service that is down a second later are two different facts.
      final HostMachine machine = HostMachine();
      machine.shell.answers(asked, saying(file: 'disabled', active: 'failed'));

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>().having(
            (StateError failure) => failure.message,
            'message',
            allOf(contains(unit), contains('ActiveState=failed'), contains('RemainAfterExit=yes')),
          ),
        ),
      );
    });

    test('a unit the manager cannot find names that too', () async {
      // `LoadState` rests on no decision this step makes and is asked for anyway: which property
      // explains a unit that did not come up is not knowable in advance, and a file that is not in
      // the directory the manager reads is the commonest of them.
      final HostMachine machine = HostMachine();
      machine.shell.answers(asked, saying(load: 'not-found', file: 'disabled', active: 'inactive'));

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>().having(
            (StateError failure) => failure.message,
            'message',
            contains('LoadState=not-found'),
          ),
        ),
      );
    });

    test('a command the manager refuses is reported as that command failing', () async {
      final HostMachine machine = machineSaying(saying(file: 'disabled'));
      machine.shell.fails('systemctl enable $unit');

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<CommandFailed>().having((CommandFailed failure) => failure.argv, 'argv', <String>[
            'systemctl',
            'enable',
            unit,
          ]),
        ),
      );
    });
  });

  group('taking it back', () {
    test('a unit this run enabled is switched off again', () async {
      final HostMachine machine = machineSaying(saying(file: 'disabled', active: 'inactive'));
      final StepContext context = machine.contextFor(under);

      await step.undo(context, await step.capture(context));
      expect(machine.changing, contains('systemctl disable --now $unit'));
    });

    test('a unit the machine ARRIVED with is left alone', () async {
      // Taking a run back is not a licence to stop a service this run did not install.
      final HostMachine machine = machineSaying(saying());
      final StepContext context = machine.contextFor(under);

      await step.undo(context, await step.capture(context));
      expect(machine.changing, isEmpty);
    });
  });

  group('what a dry run shows', () {
    test('the plan names the unit and changes nothing', () async {
      final HostMachine machine = machineSaying(saying(file: 'disabled'));
      final StepPlan plan = await step.plan(machine.contextFor(under));

      expect(plan.summary, contains(unit));
      expect(machine.changing, isEmpty);
    });
  });
}
