import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The addons of a cluster snap: reading which are on, switching them on, and waiting for them. The
/// three commands come from the row, as they would in a program file.
void main() {
  const StepName under = StepName('under_test');

  /// The commands a program row would write, under a tool name no product uses.
  const List<String> statusCommand = <String>['cluster', 'status'];
  const List<String> enableCommand = <String>['cluster', 'enable'];
  const List<String> disableCommand = <String>['cluster', 'disable'];
  const String statusKey = 'cluster status';

  /// What the status prints on a node that is running, with [on] enabled and [off] disabled.
  String status({required List<String> on, required List<String> off}) {
    final StringBuffer written = StringBuffer()
      ..writeln('the node is running')
      ..writeln('addons:')
      ..writeln('  enabled:');
    for (final String addon in on) {
      written.writeln('    $addon  # (core) an addon');
    }
    written.writeln('  disabled:');
    for (final String addon in off) {
      written.writeln('    $addon  # (core) an addon');
    }
    return written.toString();
  }

  /// What the status prints on a node that is NOT running.
  ///
  /// The snap's own shape, and the whole reason nothing here reads an exit code: it prints prose
  /// like this and EXITS ZERO. A fake shell that was told to answer with this text answers success
  /// too, which is exactly what the real one does.
  const String stopped = 'the node is not running, try starting it\n';

  /// A step wired the way a program row wires it.
  EnableAddons enabling(List<String> addons) => EnableAddons(
    addons: addons,
    statusCommand: statusCommand,
    enableCommand: enableCommand,
    disableCommand: disableCommand,
  );

  group('reading which addons are on', () {
    test('only the section listing what is on answers', () {
      // A search of the whole output finds an addon in the list of what is OFF and reports it as on.
      final Set<String> on = addonsEnabledIn(
        status(on: <String>['dns', 'rbac'], off: <String>['registry', 'gpu']),
      );
      expect(on, <String>{'dns', 'rbac'});
      expect(on, isNot(contains('registry')));
    });

    test('a stopped node names nothing, though it answered OK', () {
      expect(addonsEnabledIn(stopped), isEmpty);
    });

    test('a request carrying arguments is held against its name alone', () {
      // The snap takes `name:arguments` and answers under `name`. Comparing the whole request would
      // find the addon missing on every run and switch it on again every time.
      expect(addonNameIn('dns:185.12.64.1,185.12.64.2'), 'dns');
      expect(addonNameIn('rbac'), 'rbac');
    });

    test('the status is asked with exactly the command the row wrote', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['rbac'], off: <String>[]));

      await enabling(<String>['rbac']).check(machine.contextFor(under));
      expect(machine.shell.ran, <String>[statusKey]);
    });
  });

  group('switching the addons on', () {
    test('they go on in the order the row wrote them', () async {
      // Access control belongs first: until it is on, every access rule applied afterwards is
      // accepted and enforces nothing.
      final HostMachine machine = HostMachine();
      final List<String> on = <String>[];
      machine.shell.answers(statusKey, status(on: on, off: <String>['registry']));
      for (final String addon in <String>['rbac', 'dns', 'ingress']) {
        machine.shell.changes('cluster enable $addon', () {
          on.add(addon);
          machine.shell.answers(statusKey, status(on: on, off: <String>['registry']));
        });
      }

      final EnableAddons step = enabling(<String>['rbac', 'dns', 'ingress']);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, <String>[
        'cluster enable rbac',
        'cluster enable dns',
        'cluster enable ingress',
      ]);
    });

    test('the plan is the enable command the row wrote, with what is missing', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['rbac'], off: <String>['dns']));

      final StepPlan plan = await enabling(<String>['rbac', 'dns']).plan(machine.contextFor(under));
      expect((plan as ArgvPlan).argv, <String>[...enableCommand, 'dns']);
    });

    test('an addon that is already on is not switched on again', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['rbac'], off: <String>[]));

      expect(await enabling(<String>['rbac']).check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('an addon is asked for with the arguments its row wrote', () async {
      // Those arguments are only taken on the first switch-on, which is why they belong to the
      // request rather than to a second row.
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>[], off: <String>['dns']));

      await enabling(<String>['dns:185.12.64.1,185.12.64.2']).apply(machine.contextFor(under));
      expect(machine.changing, <String>['cluster enable dns:185.12.64.1,185.12.64.2']);
    });

    test('an addon asked for with arguments is satisfied once its name is on', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['dns'], off: <String>[]));

      expect(
        await enabling(<String>['dns:185.12.64.1']).check(machine.contextFor(under)),
        isA<Satisfied>(),
      );
      expect(machine.changing, isEmpty);
    });

    test('the undo switches off the NAME and in reverse order', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>[], off: <String>['rbac', 'dns']));

      final EnableAddons step = enabling(<String>['rbac', 'dns:185.12.64.1']);
      final StepContext context = machine.contextFor(under);
      final List<String> captured = await step.capture(context);
      await step.undo(context, captured);
      expect(machine.changing, <String>['cluster disable dns', 'cluster disable rbac']);
    });

    test('a node that cannot be read blocks rather than reporting the addons on', () async {
      final HostMachine machine = HostMachine()..shell.fails(statusKey);
      expect(await enabling(<String>['rbac']).check(machine.contextFor(under)), isA<Blocked>());
    });
  });

  group('waiting for them to show up', () {
    const WaitForAddonsEnabled step = WaitForAddonsEnabled(
      addons: <String>['rbac', 'ingress'],
      statusCommand: statusCommand,
      timeoutSeconds: 30,
      intervalSeconds: 5,
    );

    test('an addon that is listed as off is not read as on', () async {
      // The reason this wait is not a command and an answer: every addon it is waiting for stands in
      // the list of what is OFF at the moment it starts looking, so a reading of the whole output
      // would answer yes straight away.
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['rbac'], off: <String>['ingress']));

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('A STOPPED NODE DOES NOT SATISFY THIS WAIT, though its status exits zero', () async {
      // The refutation this step exists for. The status on a node that is not running prints that
      // it is stopped and returns SUCCESS, so a wait built on the exit code — or on any wait that
      // takes a zero for a yes — is satisfied by a cluster that is down. What is measured here is
      // the OUTPUT: a stopped node prints no enabled section, so nothing is on and the wait goes on
      // waiting.
      final HostMachine machine = HostMachine()..shell.answers(statusKey, stopped);

      final CommandResult answered = await machine.shell.run(
        Command.observing(statusCommand.first, arguments: statusCommand.sublist(1)),
      );
      expect(
        answered.ok,
        isTrue,
        reason:
            'the premise of this test: the stopped node answers OK, and this is the fake that '
            'reproduces it — if this ever fails the probe below is measuring the wrong thing',
      );

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(isA<WaitedTooLong>()),
        reason: 'a wait satisfied by a stopped cluster is the failure this reading exists to end',
      );
    });

    test('a wait that runs out names the addons it was waiting for', () async {
      // What it costs the run is the program row's policy: the addon was asked for and has not
      // appeared, and the steps after it notice by themselves if it really did not arrive.
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['rbac'], off: <String>['ingress']));

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.waitingFor,
            'what it waited for',
            contains('ingress'),
          ),
        ),
      );
      expect(machine.clock.elapsed.inSeconds, greaterThanOrEqualTo(30));
    });

    test('an addon that shows up while it is waiting ends the wait', () async {
      final HostMachine machine = HostMachine();
      int looks = 0;
      machine.shell
        ..answers(statusKey, status(on: <String>['rbac'], off: <String>['ingress']))
        ..changes(statusKey, () {
          looks++;
          if (looks >= 3) {
            machine.shell.answers(
              statusKey,
              status(on: <String>['rbac', 'ingress'], off: <String>[]),
            );
          }
        });

      await step.apply(machine.contextFor(under));
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a row that names an addon with its arguments still waits for the name', () async {
      // Held against the whole request, this would wait for a name the snap never prints — forever,
      // and then report a deadline nobody could explain.
      const WaitForAddonsEnabled asked = WaitForAddonsEnabled(
        addons: <String>['dns:185.12.64.1'],
        statusCommand: statusCommand,
        timeoutSeconds: 30,
        intervalSeconds: 5,
      );
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>['dns'], off: <String>[]));

      expect(await asked.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a dry run says what it would wait for instead of waiting', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(statusKey, status(on: <String>[], off: <String>['rbac']));

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains('would wait up to 30s'));
      expect(plan.summary, contains('ingress'));
      expect(machine.clock.elapsed, Duration.zero);
    });
  });
}
