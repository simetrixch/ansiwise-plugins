import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// One flag in a process's argument file, and the two measurements the network work asks of a
/// machine: its real name servers, and its packet-filtering backend.
void main() {
  const StepName under = StepName('under_test');
  const String argsPath = '/var/snap/microk8s/current/args/kube-proxy';

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
      restart: <String>['snap', 'restart', 'microk8s.daemon-kubelite'],
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

  group("the machine's real name servers", () {
    test(
      'the system resolver is asked first, and the resolver file only when it says nothing',
      () async {
        // Reading the file first answers with the local stub, which no pod can reach — and the
        // detection is then finished with a value that does not work.
        final HostMachine machine = HostMachine();
        machine.shell.answers(
          'resolvectl status',
          'Global\n  DNS Servers: 185.12.64.1 185.12.64.2\n  DNSSEC setting: no\n',
        );
        machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\n';

        expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
          '185.12.64.1',
          '185.12.64.2',
        ]);
      },
    );

    test('the local stub is dropped from BOTH sources', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers('resolvectl status', 'Global\n  DNS Servers: 127.0.0.53\n');
      machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\nnameserver 9.9.9.9\n';

      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        '9.9.9.9',
      ]);
    });

    test('an address carrying the interface it is valid on comes back without it', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers('resolvectl status', '  DNS Servers: fe80::1%eth0\n');
      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        'fe80::1',
      ]);
    });

    test('the same address named twice is named once', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        'resolvectl status',
        '  DNS Servers: 185.12.64.1 185.12.64.2\n  Current DNS Server: 185.12.64.1\n',
      );
      expect(await DetectHostUpstreamResolvers.detect(machine.contextFor(under)), <String>[
        '185.12.64.1',
        '185.12.64.2',
      ]);
    });

    test('a machine naming nothing a pod could reach is refused', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers('resolvectl status', '  DNS Servers: 127.0.0.53\n');
      machine.files.contents['/etc/resolv.conf'] = 'nameserver 127.0.0.53\n';

      const DetectHostUpstreamResolvers step = DetectHostUpstreamResolvers(
        resolvConf: '/etc/resolv.conf',
      );
      expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    });
  });

  group("the machine's packet-filtering backend", () {
    test('a machine this cannot be read from answers nothing, not a backend', () async {
      // It used to answer the modern backend here, which made "the machine filters with nft" and
      // "nothing on this machine could be read" the same sentence — and the caller had no way to
      // tell them apart afterwards.
      final HostMachine machine = HostMachine()
        ..shell.fails('readlink -f /etc/alternatives/iptables')
        ..shell.fails('readlink -f /usr/sbin/iptables');
      expect(await DetectHostIptablesBackend.detect(machine.contextFor(under)), isNull);
    });

    test('and the step blocks on it rather than reporting a reading it did not take', () async {
      // An observing step that answers Satisfied is stamped PROVEN by the engine. Satisfied here
      // would put a backend nothing measured into the record as a measurement.
      final HostMachine machine = HostMachine()
        ..shell.fails('readlink -f /etc/alternatives/iptables')
        ..shell.fails('readlink -f /usr/sbin/iptables');

      final CheckResult answer = await const DetectHostIptablesBackend(
        alternativesLink: DetectHostIptablesBackend.defaultLink,
      ).check(machine.contextFor(under));

      expect((answer as Blocked).reason, contains('could be read'));
    });

    test(
      'a machine that can be read is satisfied, so the refusal above is not the only answer',
      () async {
        final HostMachine machine = HostMachine()
          ..shell.answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/iptables-nft\n');

        expect(
          await const DetectHostIptablesBackend(
            alternativesLink: DetectHostIptablesBackend.defaultLink,
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
        await DetectHostIptablesBackend.detect(machine.contextFor(under)),
        DetectHostIptablesBackend.legacy,
      );
    });
  });
}
