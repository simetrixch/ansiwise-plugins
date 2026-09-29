import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The private-network client, put on the machine at the version the program pins.
///
/// **What a pin is for here.** An installer that is handed no version fetches whatever its makers
/// published on the day, so two machines installed a week apart run different clients, and the step
/// that holds every tool against its pin can only report the difference, at every run, with nothing
/// able to correct it.
void main() {
  const StepName under = StepName('under_test');
  const List<String> pinPrefixes = <String>['v', 'jq-'];
  const String installerPath = '/tmp/tailscale-install.sh';

  const InstallTailscaleClient pinned = InstallTailscaleClient(
    installerUrl: 'https://tailscale.com/install.sh',
    installerPath: installerPath,
    pinPrefixes: pinPrefixes,
    version: 'v1.102.4',
  );
  const InstallTailscaleClient unpinned = InstallTailscaleClient(
    installerUrl: 'https://tailscale.com/install.sh',
    installerPath: installerPath,
    pinPrefixes: pinPrefixes,
  );

  /// A machine whose client answers [version] — or one without the client, where it is null.
  HostMachine carrying(String? version) {
    final HostMachine machine = HostMachine();
    if (version == null) {
      machine.shell.fails(onThePathKey(InstallTailscaleClient.tool));
    } else {
      machine.shell
        ..answers(onThePathKey(InstallTailscaleClient.tool), '/usr/bin/tailscale\n')
        ..answers('tailscale version', '$version\n  tailscale commit: abcdef1\n');
    }
    return machine;
  }

  /// The one command that runs the installer.
  Command installerRun(HostMachine machine) =>
      machine.shell.commands.singleWhere((Command c) => c.argv.join(' ') == 'sh $installerPath');

  group('with a version the program pins', () {
    test('a client at the pin is left alone', () async {
      expect(await pinned.check(carrying('1.102.4').contextFor(under)), isA<Satisfied>());
    });

    test('a client at another version is installed again, at the pin', () async {
      // A client the installer brought on another day, which the version, not the presence, has to
      // catch.
      final HostMachine machine = carrying('1.98.10');
      expect(await pinned.check(machine.contextFor(under)), isA<Ready>());

      await pinned.apply(machine.contextFor(under));
      expect(installerRun(machine).environment[InstallTailscaleClient.versionVariable], '1.102.4');
    });

    test('a machine without the client gets it at the pin', () async {
      final HostMachine machine = carrying(null);
      expect(await pinned.check(machine.contextFor(under)), isA<Ready>());

      await pinned.apply(machine.contextFor(under));
      expect(installerRun(machine).environment[InstallTailscaleClient.versionVariable], '1.102.4');
    });

    test('the plan names the version the installer is handed', () async {
      final StepPlan plan = await pinned.plan(carrying(null).contextFor(under));
      expect(
        (plan as ArgvPlan).argv,
        containsAllInOrder(<String>['env', 'TAILSCALE_VERSION=1.102.4', 'sh', installerPath]),
      );
    });

    test('an empty version is refused rather than read as none', () async {
      // The installer reads an empty TAILSCALE_VERSION as no version at all and fetches whatever is
      // current, which is the drift the pin exists to stop.
      const InstallTailscaleClient empty = InstallTailscaleClient(
        installerUrl: 'https://tailscale.com/install.sh',
        installerPath: installerPath,
        pinPrefixes: pinPrefixes,
        version: '',
      );
      expect(await empty.check(carrying('1.102.4').contextFor(under)), isA<Blocked>());
    });
  });

  group('without a version', () {
    test(
      'THE INNOCENT NEIGHBOUR: a client that is there is left alone, whatever its version',
      () async {
        // Without this, a step that always compared versions would pass the cases above and replace
        // the client on every machine whose row names no pin.
        expect(await unpinned.check(carrying('1.98.10').contextFor(under)), isA<Satisfied>());
      },
    );

    test('the installer is handed no version', () async {
      final HostMachine machine = carrying(null);
      await unpinned.apply(machine.contextFor(under));

      expect(
        installerRun(machine).environment.containsKey(InstallTailscaleClient.versionVariable),
        isFalse,
      );
    });
  });

  test('a row may leave the version off', () {
    final ArgumentSpec version = InstallTailscaleClient.arguments.singleWhere(
      (ArgumentSpec spec) => spec.name == 'version',
    );
    expect(version.required, isFalse);
  });

  test('it cannot be taken back, because the version it replaced is kept nowhere', () {
    expect(pinned, isA<IrreversibleStep>());
    expect(pinned.irreversibleReason, contains('keeps no copy'));
  });
}
