import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Where a machine can be reached, which is what anything drawing a boundary around it has to name.
///
/// EVERY CHECK ASSERTS THE PUBLISHED LIST and never the sentence: what a later row is handed is the
/// measurement, and a message reads the same whether the list behind it is right or wrong.
void main() {
  const StepName under = StepName('under_test');
  const String listing = 'ip -4 -o addr show scope global';
  // The row names the beginnings of the interface names whose addresses are not the machine's. They
  // are made up here on purpose: what is under test is that a PREFIX the row supplies is passed over,
  // and holding it against the real names of one product's interfaces would test that product.
  const MeasureHostAddresses step = MeasureHostAddresses(
    ignoringInterfaces: <String>['podnet', 'virt', 'bridge-', 'vxlan.calico'],
  );

  /// What `ip -4 -o addr show scope global` writes, one interface per line.
  String shows(List<(String, String)> addresses) => <String>[
    for (final (String device, String cidr) in addresses)
      '2: $device    inet $cidr scope global $device\\       valid_lft forever',
  ].join('\n');

  group('what a machine says it can be reached at', () {
    test(
      'is every address it carries, as a /32 and never as the prefix it was configured with',
      () async {
        // THE WHOLE POINT OF THE /32. This machine's own address is 157.90.201.153 and it is
        // configured /32 already; the second is written /24, and naming that /24 would carve out
        // every other host on the segment along with this one.
        final HostMachine machine = HostMachine();
        machine.shell.answers(
          listing,
          shows(<(String, String)>[('eth0', '157.90.201.153/32'), ('enp7s0', '10.1.1.7/24')]),
        );

        final CheckResult result = await step.check(machine.contextFor(under));

        expect(result, isA<Satisfied>());
        expect(machine.published[MeasureHostAddresses.published], '157.90.201.153/32, 10.1.1.7/32');
      },
    );

    test('leaves out the interfaces the row named, whatever they are numbered', () async {
      // An address on one of these is not a place the machine can be reached, and they are renumbered
      // whenever the thing that made them is reconfigured — writing them down would make a machine's
      // stated addresses churn on facts that are not about the machine. Each name here carries a
      // hash or a number after the prefix, because a check against tidy names would pass on an
      // implementation matching exact names, which the very next one of these walks straight past.
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        listing,
        shows(<(String, String)>[
          ('podnet0', '10.1.181.0/32'),
          ('eth0', '157.90.201.153/32'),
          ('virt7d3f9b2a1c4', '10.1.181.7/32'),
          ('podnet-shim0', '172.17.0.1/16'),
          ('bridge-9f21c0e4', '172.18.0.1/16'),
          ('virt-tun0', '10.1.181.1/32'),
        ]),
      );

      await step.check(machine.contextFor(under));

      expect(machine.published[MeasureHostAddresses.published], '157.90.201.153/32');
    });

    test('leaves out loopback, which is every machine\'s own and identifies none', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        listing,
        shows(<(String, String)>[('lo', '127.0.0.1/8'), ('eth0', '157.90.201.153/32')]),
      );

      await step.check(machine.contextFor(under));

      expect(machine.published[MeasureHostAddresses.published], '157.90.201.153/32');
    });

    test('names an address once, however many interfaces carry it', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        listing,
        shows(<(String, String)>[('eth0', '157.90.201.153/32'), ('eth0:1', '157.90.201.153/32')]),
      );

      await step.check(machine.contextFor(under));

      expect(machine.published[MeasureHostAddresses.published], '157.90.201.153/32');
    });

    test('is written the way a list is written on one line, because nothing downstream can '
        're-separate it', () async {
      // The engine fills a slot with the measurement WHOLE (step_execution.dart), so this is the
      // last place that holds the addresses as several things. A separator that a file cannot read
      // as a list makes every reader of it parse text a second time.
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        listing,
        shows(<(String, String)>[
          ('eth0', '157.90.201.153/32'),
          ('eth1', '95.217.3.4/32'),
          ('enp7s0', '10.1.1.7/24'),
        ]),
      );

      await step.check(machine.contextFor(under));

      expect(
        machine.published[MeasureHostAddresses.published],
        '157.90.201.153/32, 95.217.3.4/32, 10.1.1.7/32',
      );
    });
  });

  group('the output a real node actually writes', () {
    // READ OFF apps4.digitacloud.app ON 2026-08-26, byte for byte, because every line above is a
    // shape this file invented and a parser is only ever wrong about the shapes nobody showed it.
    // Two things in it that no invented line here carries: the address is configured /26 and the
    // fields between the marker and it are `metric 100 brd 157.90.201.191`, so a parser reading by
    // a fixed index rather than from the marker answers with the word "metric".
    const String apps4 =
        r'2: eth0    inet 157.90.201.150/26 metric 100 brd 157.90.201.191 scope global dynamic '
        r'eth0\       valid_lft 34367sec preferred_lft 34367sec'
        '\n'
        r'3: vxlan.calico    inet 10.244.249.192/32 scope global vxlan.calico\       valid_lft '
        r'forever preferred_lft forever';

    test('is read as the node address alone, as a /32, with the pod network left out', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(listing, apps4);

      final CheckResult result = await step.check(machine.contextFor(under));

      expect(result, isA<Satisfied>());
      expect(machine.published[MeasureHostAddresses.published], '157.90.201.150/32');
    });
  });

  group('a reading that was not taken', () {
    test(
      'publishes nothing and blocks, rather than saying the machine carries no address',
      () async {
        // A machine that answered a command carries at least one address, so an empty list is the
        // question not having been put — and a boundary drawn around no address is no boundary.
        final HostMachine machine = HostMachine();
        machine.shell.answers(listing, '');

        final CheckResult result = await step.check(machine.contextFor(under));

        expect(result, isA<Blocked>());
        expect(machine.published.containsKey(MeasureHostAddresses.published), isFalse);
      },
    );

    test('a machine whose only addresses are a container network\'s is the same case', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(
        listing,
        shows(<(String, String)>[('podnet0', '10.1.181.0/32'), ('lo', '127.0.0.1/8')]),
      );

      expect(await step.check(machine.contextFor(under)), isA<Blocked>());
      expect(machine.published.containsKey(MeasureHostAddresses.published), isFalse);
    });

    test('a command that failed is not a machine with no addresses', () async {
      // No permission on the netlink socket and no `ip` on the machine both come back non-zero, and
      // folding either into an empty list would publish something no machine that answered can be
      // true of.
      final HostMachine machine = HostMachine();
      machine.shell.fails(listing, exitCode: 2, stderr: 'ip: command not found');

      await expectLater(step.check(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(machine.published.containsKey(MeasureHostAddresses.published), isFalse);
    });
  });

  group('what it does to the machine', () {
    test('nothing — it only looks', () async {
      final HostMachine machine = HostMachine();
      machine.shell.answers(listing, shows(<(String, String)>[('eth0', '157.90.201.153/32')]));

      await step.check(machine.contextFor(under));

      expect(machine.changing, isEmpty);
    });
  });
}
