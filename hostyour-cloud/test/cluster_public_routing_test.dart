import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// Steering replies on a machine whose public address arrives on one interface while another owns
/// the default route.
void main() {
  const StepName under = StepName('under_test');
  const String publicDevice = 'eth0';
  const String publicAddress = '203.0.113.10';
  const String publicGateway = '203.0.113.1';
  const String publicMac = '52:54:00:aa:bb:cc';

  /// A machine with two interfaces: the public address on one, the winning default route on another.
  ClusterMachine dualNic() {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(
        'ip -4 route show default',
        'default via 10.1.1.1 dev eth1 proto dhcp metric 100\n'
            'default via $publicGateway dev $publicDevice proto dhcp metric 200\n',
      )
      ..answers(
        'ip -4 -o addr show dev eth1',
        '3: eth1    inet 10.1.1.11/24 brd 10.1.1.255 scope global eth1\n',
      )
      ..answers(
        'ip -4 -o addr show dev $publicDevice',
        '2: $publicDevice    inet $publicAddress/26 brd 203.0.113.63 scope global $publicDevice\n',
      );
    machine.files.contents['/sys/class/net/$publicDevice/address'] = '$publicMac\n';
    return machine;
  }

  /// A machine with one interface, which is what a machine hosting the platform's own services is.
  ClusterMachine singleNic() {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(
        'ip -4 route show default',
        'default via $publicGateway dev $publicDevice proto dhcp metric 100\n',
      )
      ..answers(
        'ip -4 -o addr show dev $publicDevice',
        '2: $publicDevice    inet $publicAddress/26 brd 203.0.113.63 scope global $publicDevice\n',
      );
    machine.files.contents['/sys/class/net/$publicDevice/address'] = '$publicMac\n';
    return machine;
  }

  group('what counts as a public address', () {
    test('the private ranges are not public', () {
      for (final String address in <String>['10.1.1.11', '172.16.4.2', '192.168.1.1']) {
        expect(DetectPublicNic.isPublicIpv4(address), isFalse, reason: address);
      }
    });

    test('an address of a private overlay is not public either', () {
      // It comes out of the carrier-grade range, which a shorter list forgets — and a machine on one
      // would have its overlay address mistaken for its public one.
      expect(DetectPublicNic.isPublicIpv4('100.100.7.3'), isFalse);
    });

    test('an address a machine gave itself is not public', () {
      expect(DetectPublicNic.isPublicIpv4('169.254.169.254'), isFalse);
      expect(DetectPublicNic.isPublicIpv4('127.0.0.1'), isFalse);
    });

    test('an address on the public internet is', () {
      expect(DetectPublicNic.isPublicIpv4(publicAddress), isTrue);
    });
  });

  group('the two conditions under which the whole phase does nothing', () {
    test('a machine whose default route already leaves by the public interface', () async {
      expect(await DetectPublicNic.detect(singleNic().contextFor(under)), isNull);
    });

    test('a machine with no public address on a default-route interface', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          'ip -4 route show default',
          'default via 10.1.1.1 dev eth1 proto dhcp metric 100\n',
        )
        ..answers(
          'ip -4 -o addr show dev eth1',
          '3: eth1    inet 10.1.1.11/24 brd 10.1.1.255 scope global eth1\n',
        );
      expect(await DetectPublicNic.detect(machine.contextFor(under)), isNull);
    });

    test('a machine whose interface has no hardware address to key the drop-in on', () async {
      // Without it the drop-in cannot fold into the installer's declaration, so the phase stops
      // rather than writing one that would take the interface's address configuration away.
      final ClusterMachine machine = dualNic();
      machine.files.contents.remove('/sys/class/net/$publicDevice/address');
      expect(await DetectPublicNic.detect(machine.contextFor(under)), isNull);
    });

    test('every step of the phase does nothing on such a machine', () async {
      final ClusterMachine machine = singleNic();
      final List<Step> steps = <Step>[
        const WriteNetplanPublicSrcRouting(
          path: WriteNetplanPublicSrcRouting.defaultPath,
          table: WriteNetplanPublicSrcRouting.publicTable,
        ),
        const AssertNetplanMerged(),
        const ApplyNetplan(table: WriteNetplanPublicSrcRouting.publicTable),
        const WriteConnmarkNftTable(
          path: WriteConnmarkNftTable.defaultPath,
          mark: WriteConnmarkNftTable.defaultMark,
        ),
        const WritePublicSrcRoutingScript(
          path: WritePublicSrcRoutingScript.defaultPath,
          rulesPath: WriteConnmarkNftTable.defaultPath,
          mark: WriteConnmarkNftTable.defaultMark,
          table: WriteNetplanPublicSrcRouting.publicTable,
          priority: WritePublicSrcRoutingScript.defaultPriority,
        ),
        const WritePublicSrcRoutingUnit(
          path: WritePublicSrcRoutingUnit.defaultPath,
          scriptPath: WritePublicSrcRoutingScript.defaultPath,
          rulesPath: WriteConnmarkNftTable.defaultPath,
          mark: WriteConnmarkNftTable.defaultMark,
          table: WriteNetplanPublicSrcRouting.publicTable,
          priority: WritePublicSrcRoutingScript.defaultPriority,
        ),
        const ActivatePublicSrcRouting(
          unitName: WritePublicSrcRoutingUnit.unitName,
          mark: WriteConnmarkNftTable.defaultMark,
          table: WriteNetplanPublicSrcRouting.publicTable,
        ),
      ];
      for (final Step step in steps) {
        expect(
          await step.check(machine.contextFor(under)),
          isA<Satisfied>(),
          reason: '$step did not report itself as having nothing to do',
        );
      }
      expect(machine.files.written, isEmpty);
      expect(machine.changing, isEmpty);
    });
  });

  group('the drop-in', () {
    const WriteNetplanPublicSrcRouting step = WriteNetplanPublicSrcRouting(
      path: WriteNetplanPublicSrcRouting.defaultPath,
      table: WriteNetplanPublicSrcRouting.publicTable,
    );

    test('is keyed on the hardware address and the name, so it folds in', () async {
      final ClusterMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[WriteNetplanPublicSrcRouting.defaultPath]!;
      expect(written, contains('macaddress: "$publicMac"'));
      expect(written, contains('set-name: $publicDevice'));
    });

    test('is readable by its owner and nobody else', () async {
      // The network tool refuses to read a file anyone can read, and says so loudly rather than
      // quietly ignoring it.
      final ClusterMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      expect(machine.files.modes[WriteNetplanPublicSrcRouting.defaultPath], 0x180);
    });

    test('the four exceptions are numbered below the rule that catches everything else', () async {
      final ClusterMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[WriteNetplanPublicSrcRouting.defaultPath]!;

      for (final MapEntry<int, String> exception
          in WriteNetplanPublicSrcRouting.exceptions.entries) {
        expect(
          exception.key,
          lessThan(WriteNetplanPublicSrcRouting.catchAllPriority),
          reason: 'a lower number wins in the kernel',
        );
        expect(written, contains('to: ${exception.value}'));
      }
      expect(
        WriteNetplanPublicSrcRouting.exceptions.values,
        contains('100.64.0.0/10'),
        reason: "the certificate service checks its own answer over exactly that path",
      );
      expect(written, contains('priority: ${WriteNetplanPublicSrcRouting.catchAllPriority}'));
      expect(written, contains('via: $publicGateway'));
    });

    test('a second run finds nothing to do, so nothing is written again', () async {
      final ClusterMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final String once = machine.files.contents[WriteNetplanPublicSrcRouting.defaultPath]!;

      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'a check that is satisfied is never followed by an apply',
      );
      expect(machine.files.written, hasLength(1));
      expect(machine.files.contents[WriteNetplanPublicSrcRouting.defaultPath], once);
    });
  });

  group('the proof that the drop-in folded in', () {
    const AssertNetplanMerged step = AssertNetplanMerged();

    test('one declaration carrying both halves is the proof', () async {
      final ClusterMachine machine = dualNic();
      machine.shell.answers(
        'netplan get ethernets.$publicDevice',
        'dhcp4: true\nrouting-policy:\n  - from: $publicAddress/32\n',
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a second competing declaration shows up as one of them missing', () async {
      final ClusterMachine machine = dualNic();
      machine.shell.answers(
        'netplan get ethernets.$publicDevice',
        'routing-policy:\n  - from: $publicAddress/32\n',
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('dhcp4'));
      expect(answer.reason, contains('address configuration'));
    });

    test('it is a gate over what an earlier step did, so a dry run does not fail on it', () {
      expect(step.verifiesAnEarlierStep, isTrue);
    });
  });

  group('applying the configuration', () {
    const ApplyNetplan step = ApplyNetplan(table: WriteNetplanPublicSrcRouting.publicTable);

    test('runs when the kernel is not carrying the rule and the route', () async {
      final ClusterMachine machine = dualNic();
      machine.shell
        ..answers('ip -4 rule show', '0:\tfrom all lookup local\n')
        ..answers('ip -4 route show table 100', '')
        ..changes('netplan apply', () {
          machine.shell
            ..answers('ip -4 rule show', '10000:\tfrom $publicAddress lookup 100\n')
            ..answers('ip -4 route show table 100', 'default via $publicGateway dev eth0 onlink\n');
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, <String>['netplan apply']);
    });

    test('does not run when the kernel already carries them', () async {
      final ClusterMachine machine = dualNic();
      machine.shell
        ..answers('ip -4 rule show', '10000:\tfrom $publicAddress lookup 100\n')
        ..answers('ip -4 route show table 100', 'default via $publicGateway dev eth0 onlink\n');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('it says why a session on the public address cannot take it back', () {
      expect(step.irreversibleReason, contains('drops a session'));
    });
  });

  group('the marking rules', () {
    const WriteConnmarkNftTable step = WriteConnmarkNftTable(
      path: WriteConnmarkNftTable.defaultPath,
      mark: WriteConnmarkNftTable.defaultMark,
    );

    test('the file begins by removing the table it defines, so a reload replaces it', () async {
      final ClusterMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[WriteConnmarkNftTable.defaultPath]!;
      expect(
        written.split('\n').firstWhere((String line) => line.startsWith('destroy')),
        'destroy table inet ${WriteConnmarkNftTable.tableName}',
      );
    });

    test('the mark is clear of every other mark on the machine', () {
      // The network agent owns 0x10000-0x80000, the service proxy 0x4000 and the port publisher
      // 0x2000. Any of those would be reconciled or misread.
      final int mark = int.parse(WriteConnmarkNftTable.defaultMark.substring(2), radix: 16);
      for (final int taken in <int>[0x10000, 0x20000, 0x40000, 0x80000, 0x4000, 0x2000]) {
        expect(mark & taken, 0, reason: 'the mark shares a bit with 0x${taken.toRadixString(16)}');
      }
    });

    test('the rules mark what arrived on the public interface for the public address', () async {
      final ClusterMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[WriteConnmarkNftTable.defaultPath]!;
      expect(written, contains('iifname "$publicDevice" ip daddr $publicAddress ct state new'));
      expect(
        written,
        contains('ct mark ${WriteConnmarkNftTable.defaultMark} meta mark set ct mark'),
      );
    });

    test('an undo takes the table out of the kernel as well as off the disk', () async {
      final ClusterMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);
      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);
      expect(
        machine.changing,
        contains('nft destroy table inet ${WriteConnmarkNftTable.tableName}'),
      );
      expect(machine.files.deleted, contains(WriteConnmarkNftTable.defaultPath));
    });
  });

  group('the script and the service', () {
    const WritePublicSrcRoutingScript script = WritePublicSrcRoutingScript(
      path: WritePublicSrcRoutingScript.defaultPath,
      rulesPath: WriteConnmarkNftTable.defaultPath,
      mark: WriteConnmarkNftTable.defaultMark,
      table: WriteNetplanPublicSrcRouting.publicTable,
      priority: WritePublicSrcRoutingScript.defaultPriority,
    );

    test('the rule is MASKED, which is what makes it match at all', () async {
      // The reply carries the network agent's own mark as well, so a match on the bare value would
      // read correctly and steer nothing.
      final ClusterMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      expect(
        machine.files.contents[WritePublicSrcRoutingScript.defaultPath],
        contains(
          'fwmark ${WriteConnmarkNftTable.defaultMark}/${WriteConnmarkNftTable.defaultMark}',
        ),
      );
    });

    test('the script removes every rule at its own number before adding one', () async {
      final ClusterMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      final String written = machine.files.contents[WritePublicSrcRoutingScript.defaultPath]!;
      expect(
        written,
        contains('while ip -4 rule del priority ${WritePublicSrcRoutingScript.defaultPriority}'),
      );
      expect(written, contains('nft -f ${WriteConnmarkNftTable.defaultPath}'));
      expect(
        written.indexOf('nft -f'),
        lessThan(written.indexOf('ip -4 rule add')),
        reason: 'the rules are loaded before the rule keyed on the mark is installed',
      );
    });

    test('the script is one every account can run', () async {
      final ClusterMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      expect(machine.files.modes[WritePublicSrcRoutingScript.defaultPath], 0x1ed);
    });

    test('the service waits for the network and says how to take the kernel state away', () async {
      const WritePublicSrcRoutingUnit unit = WritePublicSrcRoutingUnit(
        path: WritePublicSrcRoutingUnit.defaultPath,
        scriptPath: WritePublicSrcRoutingScript.defaultPath,
        rulesPath: WriteConnmarkNftTable.defaultPath,
        mark: WriteConnmarkNftTable.defaultMark,
        table: WriteNetplanPublicSrcRouting.publicTable,
        priority: WritePublicSrcRoutingScript.defaultPriority,
      );
      final ClusterMachine machine = dualNic();
      await unit.apply(machine.contextFor(under));

      final String written = machine.files.contents[WritePublicSrcRoutingUnit.defaultPath]!;
      expect(written, contains('After=network-online.target'));
      expect(written, contains('Wants=network-online.target'));
      expect(written, contains('RemainAfterExit=yes'));
      expect(written, contains('ExecStop=-/usr/sbin/nft destroy table inet hostyour-public-src'));
      expect(written, contains('fwmark 0x1000/0x1000'));
      expect(machine.changing, contains('systemctl daemon-reload'));
    });
  });

  group('switching the steering on', () {
    const ActivatePublicSrcRouting step = ActivatePublicSrcRouting(
      unitName: WritePublicSrcRoutingUnit.unitName,
      mark: WriteConnmarkNftTable.defaultMark,
      table: WriteNetplanPublicSrcRouting.publicTable,
    );

    test('a service that is on with the rule in the kernel is left alone', () async {
      final ClusterMachine machine = dualNic();
      machine.shell
        ..answers('systemctl is-enabled ${WritePublicSrcRoutingUnit.unitName}', 'enabled\n')
        ..answers('systemctl is-active ${WritePublicSrcRoutingUnit.unitName}', 'active\n')
        ..answers('ip -4 rule show', '10100:\tfrom all fwmark 0x1000/0x1000 lookup 100\n');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a service that is on whose kernel state is gone is run again', () async {
      // A restart or anything that empties the machine's rule set takes the state away while the
      // service goes on reporting itself as having succeeded.
      final ClusterMachine machine = dualNic();
      machine.shell
        ..answers('systemctl is-enabled ${WritePublicSrcRoutingUnit.unitName}', 'enabled\n')
        ..answers('systemctl is-active ${WritePublicSrcRoutingUnit.unitName}', 'active\n')
        ..answers('ip -4 rule show', '0:\tfrom all lookup local\n')
        ..changes('systemctl restart ${WritePublicSrcRoutingUnit.unitName}', () {
          machine.shell.answers(
            'ip -4 rule show',
            '10100:\tfrom all fwmark 0x1000/0x1000 lookup 100\n',
          );
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, contains('systemctl restart ${WritePublicSrcRoutingUnit.unitName}'));
    });

    test('stopping the service is what takes the kernel state away', () async {
      final ClusterMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);
      await step.undo(context, await step.capture(context));
      expect(
        machine.changing,
        contains('systemctl disable --now ${WritePublicSrcRoutingUnit.unitName}'),
      );
    });
  });
}
