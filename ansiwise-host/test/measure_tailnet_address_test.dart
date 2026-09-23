import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

import 'host_fixture.dart';

/// The address this machine holds on the private network, published for a row that writes it down.
///
/// EVERY CASE ASSERTS WHAT WAS PUBLISHED: what a later row is handed is the measurement, and a
/// sentence reads the same whether the value behind it is right or wrong.
void main() {
  const StepName under = StepName('under_test');
  const MeasureTailnetAddress step = MeasureTailnetAddress();
  const String status = 'tailscale status --json';

  test('a joined machine publishes its IPv4 address, the one everything dials it by', () async {
    final HostMachine machine = HostMachine();
    machine.shell.answers(
      status,
      '{"BackendState":"Running","Self":{"TailscaleIPs":["100.64.0.7","fd7a:115c:a1e0::7"]}}',
    );

    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.published[MeasureTailnetAddress.published], '100.64.0.7');
  });

  test('a machine that has not joined is refused, and nothing is published', () async {
    final HostMachine machine = HostMachine();
    machine.shell.answers(status, '{"BackendState":"NeedsLogin"}');

    final CheckResult result = await step.check(machine.contextFor(under));

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, allOf(contains('not joined'), contains('NeedsLogin')));
    expect(machine.published, isEmpty);
  });

  test('a client that cannot be read is refused as unread, never as not joined', () async {
    final HostMachine machine = HostMachine();
    machine.shell.fails(status);

    final CheckResult result = await step.check(machine.contextFor(under));

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('could not be read'));
    expect(machine.published, isEmpty);
  });
}
