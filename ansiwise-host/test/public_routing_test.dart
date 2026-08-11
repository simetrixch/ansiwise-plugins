import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// Steering replies on a machine whose public address arrives on one interface while another owns
/// the default route.
void main() {
  const StepName under = StepName('under_test');
  const String publicDevice = 'eth0';
  const String publicAddress = '203.0.113.10';
  const String publicGateway = '203.0.113.1';
  const String publicMac = '52:54:00:aa:bb:cc';

  // What a product's program rows would state. The steps carry no defaults for these — the paths,
  // the table name and the unit name are the product's own — so the tests state them the way a
  // row does.
  const String rulesPath = '/etc/nftables.d/public-src.nft';
  const String tableName = 'public-src';
  const String scriptPath = '/usr/local/sbin/public-src-routing.sh';
  const String unitPath = '/etc/systemd/system/public-src-routing.service';
  const String unitName = 'public-src-routing.service';
  const String dropInPath = '/etc/netplan/60-public-src-routing.yaml';
  const int publicTable = 100;
  const String connmarkMark = '0x1000';
  const int rulePriority = 10100;
  const String installerKey = 'dhcp4';
  const String dropInKey = 'routing-policy';

  /// A machine with two interfaces: the public address on one, the winning default route on another.
  HostMachine dualNic() {
    final HostMachine machine = HostMachine();
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

  /// A machine with one interface, which most machines are.
  HostMachine singleNic() {
    final HostMachine machine = HostMachine();
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
      final HostMachine machine = HostMachine();
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
      final HostMachine machine = dualNic();
      machine.files.contents.remove('/sys/class/net/$publicDevice/address');
      expect(await DetectPublicNic.detect(machine.contextFor(under)), isNull);
    });

    test('every step of the phase does nothing on such a machine', () async {
      final HostMachine machine = singleNic();
      final List<Step> steps = <Step>[
        const WriteNetplanPublicSrcRouting(
          templatePath: netplanPublicSrcRoutingTemplate,
          path: dropInPath,
          table: publicTable,
        ),
        const AssertNetplanMerged(installerKey: installerKey, dropInKey: dropInKey),
        const ApplyNetplan(table: publicTable),
        const WriteConnmarkNftTable(
          templatePath: connmarkNftTableTemplate,
          path: rulesPath,
          tableName: tableName,
          mark: connmarkMark,
        ),
        const WritePublicSrcRoutingScript(
          templatePath: publicSrcRoutingScriptTemplate,
          path: scriptPath,
          rulesPath: rulesPath,
          mark: connmarkMark,
          table: publicTable,
          priority: rulePriority,
        ),
        const WritePublicSrcRoutingUnit(
          templatePath: publicSrcRoutingUnitTemplate,
          path: unitPath,
          scriptPath: scriptPath,
          tableName: tableName,
          mark: connmarkMark,
          table: publicTable,
          priority: rulePriority,
        ),
        const ActivatePublicSrcRouting(unitName: unitName, mark: connmarkMark, table: publicTable),
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
      templatePath: netplanPublicSrcRoutingTemplate,
      path: dropInPath,
      table: publicTable,
    );

    test('is keyed on the hardware address and the name, so it folds in', () async {
      final HostMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[dropInPath]!;
      expect(written, contains('macaddress: "$publicMac"'));
      expect(written, contains('set-name: $publicDevice'));
    });

    test('is readable by its owner and nobody else', () async {
      // The network tool refuses to read a file anyone can read, and says so loudly rather than
      // quietly ignoring it.
      final HostMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      expect(machine.files.modes[dropInPath], 0x180);
    });

    test('the exceptions are numbered below the rule that catches everything else', () async {
      // Read out of the drop-in that was written rather than off a constant. The ranges and their
      // numbers are the template's own text, so a constant here would say what this test wants
      // to be true instead of what the file that ships says.
      final HostMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[dropInPath]!;

      final List<_Rule> rules = _rulesOf(written);
      final List<_Rule> exceptions = rules.where((_Rule rule) => rule.to != null).toList();
      final List<_Rule> catchAll = rules.where((_Rule rule) => rule.to == null).toList();

      expect(catchAll, hasLength(1), reason: 'exactly one rule sends everything else out');
      expect(exceptions, isNotEmpty, reason: 'without an exception nothing is kept on main');
      for (final _Rule exception in exceptions) {
        expect(
          exception.priority,
          lessThan(catchAll.single.priority),
          reason: 'a lower number wins in the kernel, and ${exception.to} must stay on main',
        );
        expect(exception.table, 254, reason: '${exception.to} stays on the kernel main table');
      }
      expect(
        exceptions.map((_Rule rule) => rule.to),
        contains('100.64.0.0/10'),
        reason: 'a certificate service checks its own answer over exactly that path',
      );
      expect(catchAll.single.table, publicTable);
      expect(written, contains('via: $publicGateway'));
    });

    test('a second run finds nothing to do, so nothing is written again', () async {
      final HostMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      final String once = machine.files.contents[dropInPath]!;

      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'a check that is satisfied is never followed by an apply',
      );
      expect(machine.files.written, hasLength(1));
      expect(machine.files.contents[dropInPath], once);
    });
  });

  group('the proof that the drop-in folded in', () {
    const AssertNetplanMerged step = AssertNetplanMerged(
      installerKey: installerKey,
      dropInKey: dropInKey,
    );

    test('one declaration carrying both halves is the proof', () async {
      final HostMachine machine = dualNic();
      machine.shell.answers(
        'netplan get ethernets.$publicDevice',
        'dhcp4: true\nrouting-policy:\n  - from: $publicAddress/32\n',
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a second competing declaration shows up as one of them missing', () async {
      final HostMachine machine = dualNic();
      machine.shell.answers(
        'netplan get ethernets.$publicDevice',
        'routing-policy:\n  - from: $publicAddress/32\n',
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('dhcp4'));
      expect(answer.reason, contains('address configuration'));
    });

    test('it is a gate over what an earlier step did, so a dry run does not fail on it', () {
      expect(step.restsOnAnEarlierStep, isTrue);
    });
  });

  group('applying the configuration', () {
    const ApplyNetplan step = ApplyNetplan(table: publicTable);

    test('runs when the kernel is not carrying the rule and the route', () async {
      final HostMachine machine = dualNic();
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
      final HostMachine machine = dualNic();
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
      templatePath: connmarkNftTableTemplate,
      path: rulesPath,
      tableName: tableName,
      mark: connmarkMark,
    );

    test('the file begins by removing the table it defines, so a reload replaces it', () async {
      final HostMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[rulesPath]!;
      expect(
        written.split('\n').firstWhere((String line) => line.startsWith('destroy')),
        'destroy table inet $tableName',
      );
    });

    test('the mark is clear of every other mark on the machine', () {
      // The network agent owns 0x10000-0x80000, the service proxy 0x4000 and the port publisher
      // 0x2000. Any of those would be reconciled or misread.
      final int mark = int.parse(connmarkMark.substring(2), radix: 16);
      for (final int taken in <int>[0x10000, 0x20000, 0x40000, 0x80000, 0x4000, 0x2000]) {
        expect(mark & taken, 0, reason: 'the mark shares a bit with 0x${taken.toRadixString(16)}');
      }
    });

    test('the rules mark what arrived on the public interface for the public address', () async {
      final HostMachine machine = dualNic();
      await step.apply(machine.contextFor(under));
      final String written = machine.files.contents[rulesPath]!;
      expect(written, contains('iifname "$publicDevice" ip daddr $publicAddress ct state new'));
      expect(written, contains('ct mark $connmarkMark meta mark set ct mark'));
    });

    test('an undo takes the table out of the kernel as well as off the disk', () async {
      final HostMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);
      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);
      expect(machine.changing, contains('nft destroy table inet $tableName'));
      expect(machine.files.deleted, contains(rulesPath));
    });
  });

  group('the script and the service', () {
    const WritePublicSrcRoutingScript script = WritePublicSrcRoutingScript(
      templatePath: publicSrcRoutingScriptTemplate,
      path: scriptPath,
      rulesPath: rulesPath,
      mark: connmarkMark,
      table: publicTable,
      priority: rulePriority,
    );

    const WritePublicSrcRoutingUnit unit = WritePublicSrcRoutingUnit(
      templatePath: publicSrcRoutingUnitTemplate,
      path: unitPath,
      scriptPath: scriptPath,
      tableName: tableName,
      mark: connmarkMark,
      table: publicTable,
      priority: rulePriority,
    );

    test('the rule is MASKED, which is what makes it match at all', () async {
      // The reply carries the network agent's own mark as well, so a match on the bare value would
      // read correctly and steer nothing.
      final HostMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      expect(machine.files.contents[scriptPath], contains('fwmark $connmarkMark/$connmarkMark'));
    });

    test('the script removes every rule at its own number before adding one', () async {
      final HostMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      final String written = machine.files.contents[scriptPath]!;
      expect(written, contains('while ip -4 rule del priority $rulePriority'));
      expect(written, contains('nft -f $rulesPath'));
      expect(
        written.indexOf('nft -f'),
        lessThan(written.indexOf('ip -4 rule add')),
        reason: 'the rules are loaded before the rule keyed on the mark is installed',
      );
    });

    test('the script is one every account can run', () async {
      final HostMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      expect(machine.files.modes[scriptPath], 0x1ed);
    });

    test('the script installs exactly the rule the undo removes', () async {
      // The script's add line and the undo's arguments are two statements of one rule, and two
      // statements of one rule can disagree — a machine would then be left carrying a rule
      // nothing on it knows how to take away.
      final HostMachine machine = dualNic();
      await script.apply(machine.contextFor(under));
      final String written = machine.files.contents[scriptPath]!;

      expect(written, contains('ip ${script.ruleArguments('add').join(' ')}\n'));
      expect(
        script.ruleArguments('add').join(' ').replaceAll(' add ', ' del '),
        script.ruleArguments('del').join(' '),
      );
    });

    test('the service waits for the network and says how to take the kernel state away', () async {
      final HostMachine machine = dualNic();
      await unit.apply(machine.contextFor(under));

      final String written = machine.files.contents[unitPath]!;
      expect(written, contains('After=network-online.target'));
      expect(written, contains('Wants=network-online.target'));
      expect(written, contains('RemainAfterExit=yes'));
      expect(written, contains('ExecStop=-/usr/sbin/nft destroy table inet $tableName'));
      expect(written, contains('fwmark 0x1000/0x1000'));
      expect(machine.changing, contains('systemctl daemon-reload'));
    });

    test('what the service stops is exactly what the script started', () async {
      final HostMachine machine = dualNic();
      await unit.apply(machine.contextFor(under));

      expect(
        machine.files.contents[unitPath],
        contains('ExecStop=-/usr/sbin/ip ${script.ruleArguments('del').join(' ')}\n'),
      );
    });

    test("the service's name is the file's own base name, so the two cannot come apart", () {
      expect(unit.unitName, unitName);
    });
  });

  group('the template a file is written from', () {
    const WriteConnmarkNftTable step = WriteConnmarkNftTable(
      templatePath: connmarkNftTableTemplate,
      path: rulesPath,
      tableName: tableName,
      mark: connmarkMark,
    );

    test('a machine that carries none is BLOCKED, never satisfied', () async {
      // The two answers look alike from outside and are opposites. Satisfied says this machine has
      // no business with the file; a machine whose template did not travel with its programs needs
      // the file as much as any other, and reporting the first would leave it with no rule set and
      // a run that said every step was fine.
      final HostMachine machine = dualNic();
      machine.files.contents.remove(connmarkNftTableTemplate);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(connmarkNftTableTemplate));
    });

    test('and its plan says so rather than failing to be produced', () async {
      final HostMachine machine = dualNic();
      machine.files.contents.remove(connmarkNftTableTemplate);

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains(connmarkNftTableTemplate));
      expect(machine.files.written, isEmpty);
    });

    test('a machine that needs no such file says so, template or no template', () async {
      // The order of the two questions. A machine that steers nothing has no business with the rule
      // set at all, so whether its installation carries the template is not a question about it —
      // and asking it first would kill the run on every single-interface machine of an installation
      // whose templates did not travel, instead of on the machines that actually need them.
      final HostMachine machine = singleNic();
      machine.files.contents.remove(connmarkNftTableTemplate);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains('nothing is steered'));
    });

    test('a dry run still shows the whole file, not a mention of a template', () async {
      // The plan an operator reads must be the rendered rule set, byte for byte. A plan that had
      // become "would render a template" would be a weaker plan than a composed one.
      final HostMachine machine = dualNic();
      final StepPlan plan = await step.plan(machine.contextFor(under));

      expect(plan, isA<DiffPlan>());
      final DiffPlan diff = plan as DiffPlan;
      expect(diff.path, rulesPath);
      expect(diff.after, contains('iifname "$publicDevice" ip daddr $publicAddress'));
      expect(diff.after, contains('ct mark $connmarkMark'));
      expect(diff.after, isNot(contains('<')));
      expect(machine.files.written, isEmpty);
    });

    test('a slot nothing fills is refused rather than written onto the machine', () async {
      final HostMachine machine = dualNic();
      machine.files.contents[connmarkNftTableTemplate] =
          '${machine.files.contents[connmarkNftTableTemplate]}# <interface>\n';

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused failure) => failure.message,
            'message',
            allOf(contains('<interface>'), contains(connmarkNftTableTemplate)),
          ),
        ),
      );
      expect(machine.files.written, isEmpty);
    });

    test('a value with no slot to go into is refused for the same reason', () {
      const Template template = Template(path: 'somewhere.tpl', text: 'mark <mark>\n');
      expect(
        () => template.filledWith(<String, String>{'mark': '0x1000', 'device': 'eth0'}),
        throwsA(
          isA<TemplateRefused>().having(
            (TemplateRefused failure) => failure.message,
            'message',
            contains('<device>'),
          ),
        ),
      );
    });
  });

  group('switching the steering on', () {
    const ActivatePublicSrcRouting step = ActivatePublicSrcRouting(
      unitName: unitName,
      mark: connmarkMark,
      table: publicTable,
    );

    test('a service that is on with the rule in the kernel is left alone', () async {
      final HostMachine machine = dualNic();
      machine.shell
        ..answers('systemctl is-enabled $unitName', 'enabled\n')
        ..answers('systemctl is-active $unitName', 'active\n')
        ..answers('ip -4 rule show', '10100:\tfrom all fwmark 0x1000/0x1000 lookup 100\n');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a service that is on whose kernel state is gone is run again', () async {
      // A restart or anything that empties the machine's rule set takes the state away while the
      // service goes on reporting itself as having succeeded.
      final HostMachine machine = dualNic();
      machine.shell
        ..answers('systemctl is-enabled $unitName', 'enabled\n')
        ..answers('systemctl is-active $unitName', 'active\n')
        ..answers('ip -4 rule show', '0:\tfrom all lookup local\n')
        ..changes('systemctl restart $unitName', () {
          machine.shell.answers(
            'ip -4 rule show',
            '10100:\tfrom all fwmark 0x1000/0x1000 lookup 100\n',
          );
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, contains('systemctl restart $unitName'));
    });

    test('stopping the service is what takes the kernel state away', () async {
      final HostMachine machine = dualNic();
      final StepContext context = machine.contextFor(under);
      await step.undo(context, await step.capture(context));
      expect(machine.changing, contains('systemctl disable --now $unitName'));
    });
  });
}

/// One routing-policy rule as the drop-in that was written states it.
final class _Rule {
  const _Rule({required this.priority, required this.table, this.to});

  /// The number the kernel weighs it at.
  final int priority;

  /// The table it looks the reply up in.
  final int table;

  /// The range it is an exception for, or null where it catches everything else.
  final String? to;
}

/// Every routing-policy rule of [dropIn], read back out of the text that was written.
List<_Rule> _rulesOf(String dropIn) {
  final List<_Rule> rules = <_Rule>[];
  String? to;
  int? table;
  for (final String line in dropIn.split('\n')) {
    final String said = line.trim();
    if (said.startsWith('- from:')) {
      to = null;
      table = null;
      continue;
    }
    if (said.startsWith('to:')) {
      to = said.substring('to:'.length).trim();
      continue;
    }
    if (said.startsWith('table:')) {
      table = int.tryParse(said.substring('table:'.length).trim());
      continue;
    }
    if (said.startsWith('priority:') && table != null) {
      rules.add(
        _Rule(priority: int.parse(said.substring('priority:'.length).trim()), table: table, to: to),
      );
    }
  }
  return rules;
}
