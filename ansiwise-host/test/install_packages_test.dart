/// Packages a machine needs, put on it while something else is already using apt.
///
///   dart test test/install_packages_test.dart
///
/// WHAT IS BEING HELD is that this step does not lose a race it was always going to be in. Ubuntu
/// starts `unattended-upgrades` on its own shortly after boot, so a machine that was just restored
/// or just provisioned is holding the dpkg lock through the first minutes of its life — which is
/// exactly when a first installation reaches this row, four steps into the first program it runs.
/// Measured on a real machine: `apt-get install --yes apache2-utils returned 100 / E: Could not get
/// lock /var/lib/dpkg/lock-frontend. It is held by process 14400 (unattended-upgr)`.
///
/// The fixtures below answer the way that machine answered: apt refuses unless it was asked to wait
/// for the lock. A step that stops asking meets the refusal, and every case here goes red.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/src/steps/host/install_packages.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// What apt says when somebody else holds the lock, in its own words.
const String heldByAnother =
    'E: Could not get lock /var/lib/dpkg/lock-frontend. It is held by process 14400 '
    '(unattended-upgr)\n'
    'E: Unable to acquire the dpkg frontend lock (/var/lib/dpkg/lock-frontend), is another process '
    'using it?';

void main() {
  const StepName under = StepName('install_packages');
  const String package = 'apache2-utils';
  const InstallPackages step = InstallPackages(<String>[package]);

  /// A machine holding the lock: apt answers only what was asked to wait, and refuses the rest.
  HostMachine busyWithUnattendedUpgrades() {
    final HostMachine machine = HostMachine();
    machine.shell
      ..fails('dpkg-query -W -f=\${Status} $package')
      // The bare forms are what a step that stopped asking would send.
      ..fails('apt-get update', exitCode: 100, stderr: heldByAnother)
      ..fails('apt-get install --yes $package', exitCode: 100, stderr: heldByAnother)
      // The waiting forms are what apt answers a caller willing to wait for it.
      ..changes('apt-get -o DPkg::Lock::Timeout=600 update', () {})
      ..changes('apt-get -o DPkg::Lock::Timeout=600 install --yes $package', () {
        machine.shell.answers('dpkg-query -W -f=\${Status} $package', 'install ok installed');
      });
    return machine;
  }

  test('installs onto a machine whose package manager is already busy', () async {
    final HostMachine machine = busyWithUnattendedUpgrades();

    await step.apply(machine.contextFor(under));

    expect(
      await step.check(machine.contextFor(under)),
      isA<Satisfied>(),
      reason:
          'unattended-upgrades holding the lock is the normal state of a freshly booted machine, '
          'and it clears itself — a run that fails on it fails for a condition that was never wrong',
    );
  });

  test('says how long it is willing to wait, in the argv a record keeps', () async {
    final HostMachine machine = busyWithUnattendedUpgrades();

    await step.apply(machine.contextFor(under));

    final Iterable<String> apt = machine.shell.ran.where(
      (String argv) => argv.startsWith('apt-get '),
    );
    expect(apt, isNotEmpty);
    for (final String argv in apt) {
      expect(
        argv,
        contains('-o DPkg::Lock::Timeout='),
        reason:
            'a bound that stands in the argv is one a record shows, so a reader is not left to '
            'guess whether the run waited at all',
      );
    }
  });

  test(
    'the plan a dry run shows carries it too, because it is the command that will run',
    () async {
      final HostMachine machine = busyWithUnattendedUpgrades();

      final StepPlan planned = await step.plan(machine.contextFor(under));

      expect(planned, isA<ArgvPlan>());
      expect(
        (planned as ArgvPlan).argv,
        containsAllInOrder(<String>['-o', 'DPkg::Lock::Timeout=600']),
      );
    },
  );

  test('INNOCENT CASE: an apt failure that is not the lock still fails the step', () async {
    final HostMachine machine = HostMachine();
    machine.shell
      ..fails('dpkg-query -W -f=\${Status} $package')
      ..changes('apt-get -o DPkg::Lock::Timeout=600 update', () {})
      ..fails(
        'apt-get -o DPkg::Lock::Timeout=600 install --yes $package',
        exitCode: 100,
        stderr: 'E: Unable to locate package $package',
      );

    expect(
      () => step.apply(machine.contextFor(under)),
      throwsA(isA<CommandFailed>()),
      reason: 'waiting for a lock is not the same as waiting out every refusal apt can give',
    );
  });

  test('INNOCENT CASE: a machine that already carries the package is not touched', () async {
    final HostMachine machine = HostMachine();
    machine.shell.answers('dpkg-query -W -f=\${Status} $package', 'install ok installed');

    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.shell.ran.where((String argv) => argv.startsWith('apt-get ')), isEmpty);
  });
}
