import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The network agent's packet-filtering backend, held to the machine's own.
void main() {
  const StepName under = StepName('align_calico_backend');
  const String felixBackend =
      'kubectl get felixconfiguration/default -o jsonpath={.spec.iptablesBackend}';
  const AlignCalicoBackend step = AlignCalicoBackend(rolloutTimeoutSeconds: 120);

  test('an agent that works it out for itself is left alone', () async {
    final ClusterMachine machine = ClusterMachine()..shell.answers(felixBackend, 'Auto\n');
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('an empty answer is the same thing', () async {
    final ClusterMachine machine = ClusterMachine()..shell.answers(felixBackend, '');
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
  });

  test('an agent pinned against the machine is repinned, and no rule is touched', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(felixBackend, 'Legacy\n')
      ..answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/xtables-nft-multi\n')
      ..changes(
        'kubectl patch felixconfiguration/default --type merge -p '
        '{"spec":{"iptablesBackend":"NFT"}}',
        () => machine.shell.answers(felixBackend, 'NFT\n'),
      );

    final StepContext context = machine.contextFor(under);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(await step.check(context), isA<Satisfied>());
    expect(
      machine.changing.join('\n'),
      isNot(anyOf(contains('iptables -F'), contains('iptables-legacy'))),
      reason: 'flushing the other backend wiped the ingress translation rules once',
    );
  });

  test('an agent matching a machine on the older backend is finished work', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(felixBackend, 'Legacy\n')
      ..answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/xtables-legacy-multi\n');
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a machine this cannot be read from is held to the modern backend', () async {
    // The fallback direction is chosen: pinning the agent to the older backend on a machine that
    // is really on the modern one is the split this measurement exists to prevent.
    final ClusterMachine machine = ClusterMachine()
      ..shell.answers(felixBackend, 'NFT\n')
      ..shell.fails('readlink -f /etc/alternatives/iptables')
      ..shell.fails('readlink -f /usr/sbin/iptables');
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
  });

  test('the pin the agent carried is what an undo puts back', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(felixBackend, 'Legacy\n')
      ..answers('readlink -f /etc/alternatives/iptables', '/usr/sbin/xtables-nft-multi\n');

    final StepContext context = machine.contextFor(under);
    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);

    expect(
      machine.changing.join('\n'),
      contains('{"spec":{"iptablesBackend":"Legacy"}}'),
      reason: 'the pin read before the change is what goes back',
    );
  });
}
