import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

// One host name kept on this machine: a service whose public address a request from the machine
// itself reaches only through its router.

void main() {
  const StepName under = StepName('under_test');
  const SetHostAddress step = SetHostAddress(host: 'store.cluster.example', address: '127.0.0.1');
  const String standard = '127.0.0.1 localhost\n::1 localhost ip6-localhost\n';

  HostMachine machine(String hosts) => HostMachine()..files.contents['/etc/hosts'] = hosts;
  String hostsOf(HostMachine m) => m.files.contents['/etc/hosts']!;

  test('appends the name and leaves every other line as it stood', () async {
    final HostMachine m = machine(standard);
    final StepContext context = m.contextFor(under);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(hostsOf(m), '${standard}127.0.0.1 store.cluster.example\n');
    expect(await step.check(m.contextFor(under)), isA<Satisfied>());
  });

  test(
    'PLANTED DEFECT: takes the name out of an earlier line that maps it elsewhere, because the first line decides',
    () async {
      final HostMachine m = machine('82.136.98.7 store.cluster.example cluster.example\n$standard');
      await step.apply(m.contextFor(under));
      expect(
        hostsOf(m),
        '82.136.98.7 cluster.example\n${standard}127.0.0.1 store.cluster.example\n',
      );
    },
  );

  test('drops a line left with no name, and keeps comments', () async {
    final HostMachine m = machine(
      '# kept\n82.136.98.7 store.cluster.example # old\n'
      '10.0.0.9 cluster.example store.cluster.example # also kept\n$standard',
    );
    await step.apply(m.contextFor(under));
    expect(
      hostsOf(m),
      '# kept\n10.0.0.9 cluster.example # also kept\n${standard}127.0.0.1 store.cluster.example\n',
    );
  });

  test(
    'writes nothing where the first line naming the host already maps it to the address',
    () async {
      final HostMachine m = machine('${standard}127.0.0.1 store.cluster.example\n');
      final StepContext context = m.contextFor(under);
      expect(await step.check(context), isA<Satisfied>());
      await step.apply(context);
      expect(m.files.written, isEmpty);
    },
  );

  test('the undo writes the file back as it was read before the apply', () async {
    final HostMachine m = machine(standard);
    final StepContext context = m.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);
    expect(hostsOf(m), standard);
  });

  test(
    'refuses an address that is none or missing, and a host name a hosts file cannot carry',
    () async {
      final HostMachine m = machine(standard);
      const SetHostAddress badAddress = SetHostAddress(host: 'store.example', address: 'localhost');
      const SetHostAddress badHost = SetHostAddress(host: 'store example', address: '127.0.0.1');
      const SetHostAddress noAddress = SetHostAddress(host: 'store.example', address: null);
      expect(await badAddress.check(m.contextFor(under)), isA<Blocked>());
      expect(await badHost.check(m.contextFor(under)), isA<Blocked>());
      expect(await noAddress.check(m.contextFor(under)), isA<Blocked>());
    },
  );

  test('takes an IPv6 address as well as an IPv4 one', () async {
    const SetHostAddress v6 = SetHostAddress(host: 'store.example', address: 'fd7a:115c:a1e0::1');
    expect(await v6.check(machine(standard).contextFor(under)), isA<Ready>());
  });
}
