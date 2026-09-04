import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// One flag in a process's argument file, and the two measurements the network work asks of a
/// machine: its packet-filtering backend, and the source ports it opens its own outgoing
/// connections from.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = '/etc/proxy/args';

  group('a flag in the file a process is started with', () {
    // The row a program writes: which backend a service paints its rules into is one line of one
    // argument file, and the row says which file, which flag and what it is set to.
    // The mode and the restart come from the row for the same reason the flag does: they are facts
    // about the machine in front of the run, and the step knows none of them by itself.
    const SetProcessFlag proxyMode = SetProcessFlag(
      argsPath: argsPath,
      flag: '--proxy-mode',
      value: 'nftables',
      fileMode: 384,
      restart: <String>['snap', 'restart', 'proxy-daemon'],
    );

    test('the arguments carry the flag exactly once', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=ipvs\n';

      const SetProcessFlag step = proxyMode;
      final StepContext context = machine.contextFor(under);
      await step.apply(context);

      final Iterable<String> flags = machine.files.contents[argsPath]!
          .split('\n')
          .where((String each) => each.startsWith('--proxy-mode='));
      expect(flags, <String>['--proxy-mode=nftables']);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run neither appends nor restarts anything', () async {
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

      const SetProcessFlag step = proxyMode;
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
      expect(machine.changing, isEmpty);
    });

    test('a machine with no such file is refused rather than given one', () async {
      final CheckResult answer = await proxyMode.check(HostMachine().contextFor(under));
      expect((answer as Blocked).reason, contains(argsPath));
    });

    test('the value as it stood is what an undo puts back, not the line taken out', () async {
      // Several rows write this one file, so a row that removed its own line at undo time would
      // leave the machine with no backend where it had one before the run.
      final HostMachine machine = HostMachine();
      machine.files.contents[argsPath] = '--proxy-mode=ipvs\n';
      final StepContext context = machine.contextFor(under);

      final String? captured = await proxyMode.capture(context);
      await proxyMode.apply(context);
      await proxyMode.undo(context, captured);
      expect(machine.files.contents[argsPath], '--proxy-mode=ipvs\n');
    });
  });

  group("the machine's packet-filtering backend", () {
    test('a machine this cannot be read from answers nothing, not a backend', () async {
      // Answering the modern backend here would make "the machine filters with nft" and "nothing on
      // this machine could be read" the same sentence, with no way for the caller to tell them
      // apart afterwards.
      final HostMachine machine = HostMachine()
        ..shell.fails('readlink -f /etc/alternatives/iptables')
        ..shell.fails('readlink -f /usr/sbin/iptables');
      expect(await MeasureHostIptablesBackend.measure(machine.contextFor(under)), isNull);
    });

    test('and the step blocks on it rather than reporting a reading it did not take', () async {
      // An observing step that answers Satisfied is stamped PROVEN by the engine. Satisfied here
      // would put a backend nothing measured into the record as a measurement.
      final HostMachine machine = HostMachine()
        ..shell.fails('readlink -f /etc/alternatives/iptables')
        ..shell.fails('readlink -f /usr/sbin/iptables');

      final CheckResult answer = await const MeasureHostIptablesBackend(
        alternativesLink: MeasureHostIptablesBackend.defaultLink,
      ).check(machine.contextFor(under));

      expect((answer as Blocked).reason, contains('could be read'));
    });

    test(
      'a machine that can be read is satisfied, so the refusal above is not the only answer',
      () async {
        final HostMachine machine = HostMachine()
          ..shell.answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/iptables-nft\n');

        expect(
          await const MeasureHostIptablesBackend(
            alternativesLink: MeasureHostIptablesBackend.defaultLink,
          ).check(machine.contextFor(under)),
          isA<Satisfied>(),
        );
      },
    );

    test('a machine set to the older one is reported as it is', () async {
      final HostMachine machine = HostMachine()
        ..shell.answers(
          'readlink -f /etc/alternatives/iptables',
          '/usr/sbin/xtables-legacy-multi\n',
        );
      expect(
        await MeasureHostIptablesBackend.measure(machine.contextFor(under)),
        MeasureHostIptablesBackend.legacy,
      );
    });
  });

  group('the ports the machine opens its own connections from', () {
    // What the kernel writes into this file: the low and the high port with a tab between them and a
    // newline after. The two numbers are what something masquerading another address range behind
    // this machine has to be held to, because the network the machine hangs on may carry the answer
    // back for these ports and for no others.
    const String kernelSays = '32768\t60999\n';

    test(
      'the two numbers the kernel names are what is published, separated by one space',
      () async {
        final HostMachine machine = HostMachine();
        machine.files.contents[MeasureHostLocalPortRange.path] = kernelSays;

        expect(
          await const MeasureHostLocalPortRange().check(machine.contextFor(under)),
          isA<Satisfied>(),
        );
        expect(machine.published[const MeasurementName('local_port_range')], '32768 60999');
      },
    );

    test(
      'a machine tuned to other ports publishes those, so no range is written down here',
      () async {
        final HostMachine machine = HostMachine();
        machine.files.contents[MeasureHostLocalPortRange.path] = '1024 65535\n';

        expect(await MeasureHostLocalPortRange.measure(machine.contextFor(under)), '1024 65535');
      },
    );

    test('a machine this cannot be read from answers nothing, not a range', () async {
      // Answering with the whole port space here would make "this machine opens its own connections
      // from every port" and "nothing here could be read" the same sentence, and whatever is held to
      // the value cannot tell them apart afterwards.
      expect(await MeasureHostLocalPortRange.measure(HostMachine().contextFor(under)), isNull);
    });

    test('and the step blocks on it rather than publishing a range it did not read', () async {
      // An observing step that answers Satisfied is stamped PROVEN by the engine.
      final HostMachine machine = HostMachine();

      final CheckResult answer = await const MeasureHostLocalPortRange().check(
        machine.contextFor(under),
      );

      expect((answer as Blocked).reason, contains('no pair of port numbers'));
      expect(machine.published, isEmpty);
    });

    // Five shapes the file could hold that are not a pair of ports: nothing, one number, three
    // numbers, two words, and a number that is no port.
    for (final String unusable in <String>[
      '',
      '32768',
      '32768 60999 61000',
      'low high',
      '0 60999',
    ]) {
      test('a file reading "$unusable" names no pair of ports', () async {
        final HostMachine machine = HostMachine();
        machine.files.contents[MeasureHostLocalPortRange.path] = '$unusable\n';

        expect(await MeasureHostLocalPortRange.measure(machine.contextFor(under)), isNull);
      });
    }
  });
}
