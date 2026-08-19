import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// A long-running service of the machine: the unit another program row's work is started by, and
/// the switch that turns it on.
///
/// The one property with its own planted defect here is `KillMode=process`. The service manager's
/// default kill mode takes the unit's whole control group with every restart — detached children
/// included, because a detached process gets a new session and not a new control group — and
/// nothing on the machine ever reports why the children vanished. So the step is what refuses a
/// unit that lost the line, and these tests prove the refusal can really go red.
void main() {
  const StepName under = StepName('under_test');

  // What a product's program rows would state. The steps carry no defaults for these — the unit's
  // path and the command are the product's own — so the tests state them the way a row does.
  const String unitPath = '/etc/systemd/system/serve-deployments.service';
  const String unitName = 'serve-deployments.service';
  const List<String> command = <String>[
    '/usr/local/bin/deploy-api',
    'serve',
    '--listen',
    '0.0.0.0:8642',
  ];
  const String workingDirectory = '/srv/programs';

  WriteServiceUnit writer({bool keepsDetachedChildren = true}) => WriteServiceUnit(
    templatePath: serviceUnitTemplate,
    path: unitPath,
    command: command,
    workingDirectory: workingDirectory,
    keepsDetachedChildren: keepsDetachedChildren,
    elevated: true,
  );

  group('writing the unit', () {
    test('the rendered unit carries the command and lands at the path', () async {
      final HostMachine machine = HostMachine();
      final WriteServiceUnit step = writer();

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
      await step.apply(machine.contextFor(under));

      final String written = machine.files.contents[unitPath]!;
      expect(written, contains('ExecStart=${command.join(' ')}'));
      expect(written, contains('WorkingDirectory=$workingDirectory'));
      expect(written, isNot(contains('<')), reason: 'no slot may reach the machine unfilled');
    });

    test('the service manager is told about the file it did not watch for', () async {
      final HostMachine machine = HostMachine();
      await writer().apply(machine.contextFor(under));
      expect(machine.shell.ran, contains('systemctl daemon-reload'));
    });

    test('a second run finds the unit already saying what this run writes', () async {
      final HostMachine machine = HostMachine();
      final WriteServiceUnit step = writer();
      await step.apply(machine.contextFor(under));
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('PLANTED DEFECT: a unit that lost KillMode=process is refused, not written', () async {
      final HostMachine machine = HostMachine();
      // The template as shipped, with the one load-bearing line taken out — which is exactly the
      // edit a well-meaning cleanup makes, because the line looks inert next to Restart=always.
      machine.files.contents[serviceUnitTemplate] = machine.files.contents[serviceUnitTemplate]!
          .split('\n')
          .where((String line) => line.trim() != WriteServiceUnit.keepsChildrenLine)
          .join('\n');

      final CheckResult result = await writer().check(machine.contextFor(under));
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(WriteServiceUnit.keepsChildrenLine));
      expect(
        machine.files.contents.containsKey(unitPath),
        isFalse,
        reason: 'a refused unit must not reach the machine',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a row that never claimed detached children takes the same '
        'template as it stands', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[serviceUnitTemplate] = machine.files.contents[serviceUnitTemplate]!
          .split('\n')
          .where((String line) => line.trim() != WriteServiceUnit.keepsChildrenLine)
          .join('\n');

      expect(
        await writer(keepsDetachedChildren: false).check(machine.contextFor(under)),
        isA<Ready>(),
      );
    });

    test('undo takes a unit this run created away and stops the service first', () async {
      final HostMachine machine = HostMachine();
      final WriteServiceUnit step = writer();
      final String? before = await step.capture(machine.contextFor(under));
      await step.apply(machine.contextFor(under));

      await step.undo(machine.contextFor(under), before);
      expect(machine.files.contents.containsKey(unitPath), isFalse);
      expect(machine.shell.ran, contains('systemctl disable --now $unitName'));
    });

    test('undo puts back a unit that was already there', () async {
      final HostMachine machine = HostMachine();
      const String theirs = '[Unit]\nDescription=somebody else wrote this\n';
      machine.files.contents[unitPath] = theirs;

      final WriteServiceUnit step = writer();
      final String? before = await step.capture(machine.contextFor(under));
      await step.apply(machine.contextFor(under));
      expect(machine.files.contents[unitPath], isNot(theirs));

      await step.undo(machine.contextFor(under), before);
      expect(machine.files.contents[unitPath], theirs);
    });
  });

  group('switching the service on', () {
    const ActivateServiceUnit step = ActivateServiceUnit(unitName: unitName);

    test('a machine where it is neither enabled nor active has work to do', () async {
      final HostMachine machine = HostMachine();
      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test(
      'enabled but crashed is still work to do — active alone is not the state either',
      () async {
        final HostMachine enabledOnly = HostMachine();
        enabledOnly.shell.answers('systemctl is-enabled $unitName', 'enabled\n');
        expect(await step.check(enabledOnly.contextFor(under)), isA<Ready>());

        final HostMachine activeOnly = HostMachine();
        activeOnly.shell.answers('systemctl is-active $unitName', 'active\n');
        expect(await step.check(activeOnly.contextFor(under)), isA<Ready>());
      },
    );

    test('enabled and active together is the state, and nothing more is asked', () async {
      final HostMachine machine = HostMachine();
      machine.shell
        ..answers('systemctl is-enabled $unitName', 'enabled\n')
        ..answers('systemctl is-active $unitName', 'active\n');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test(
      'the apply enables and then restarts, so a rewritten unit is what ends up running',
      () async {
        final HostMachine machine = HostMachine();
        await step.apply(machine.contextFor(under));
        expect(
          machine.shell.ran,
          containsAllInOrder(<String>['systemctl enable $unitName', 'systemctl restart $unitName']),
        );
      },
    );

    test('undo leaves a service alone that already came back after a restart', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers('systemctl is-enabled $unitName', 'enabled\n');
      final bool wasEnabled = await step.capture(machine.contextFor(under));
      await step.undo(machine.contextFor(under), wasEnabled);
      expect(machine.shell.ran, isNot(contains('systemctl disable --now $unitName')));
    });

    test('undo switches off what this run switched on', () async {
      final HostMachine machine = HostMachine();
      final bool wasEnabled = await step.capture(machine.contextFor(under));
      await step.apply(machine.contextFor(under));
      await step.undo(machine.contextFor(under), wasEnabled);
      expect(machine.shell.ran, contains('systemctl disable --now $unitName'));
    });
  });
}
