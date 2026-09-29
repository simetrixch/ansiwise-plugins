import 'dart:convert' show jsonDecode;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The pool for the new range, put in before the default pool goes.
///
/// **The record it answers.** At every first installation the verify step found the default pool
/// back on the old range and deleted it once more: an agent that started with its old environment
/// found no IPv4 pool and created one. With a pool for the new range standing first, the agent
/// finds a pool and creates none.
void main() {
  const StepName under = StepName('create_ipv4_ippool_for_pod_cidr');
  const String podCidr = '10.244.0.0/16';
  const String poolPath = '/var/lib/pools/pod-cidr-ipv4-ippool.json';
  const String pools = 'kubectl get ippool -o ${RemoveDefaultIpv4Ippool.poolsOutput}';
  const String applyPool = 'kubectl apply -f $poolPath';
  const CreateIpv4IppoolForPodCidr step = CreateIpv4IppoolForPodCidr(
    podCidr: podCidr,
    poolManifestPath: poolPath,
  );

  /// How the step asks the agent's set for [variable].
  String declared(String variable) =>
      'kubectl -n kube-system get daemonset calico-node -o '
      'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="$variable")].value}';

  /// A fresh cluster on the default range, whose agent is set up with [environment].
  ///
  /// The apply is carried out: once it runs, the cluster also holds the pool it applied.
  ClusterMachine onTheDefaultRange({Map<String, String> environment = const <String, String>{}}) {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(pools, 'default-ipv4-ippool=10.1.0.0/16\n')
      ..changes(applyPool, () {
        machine.shell.answers(
          pools,
          'default-ipv4-ippool=10.1.0.0/16\n${CreateIpv4IppoolForPodCidr.poolName}=$podCidr\n',
        );
      });
    environment.forEach((String variable, String value) {
      machine.shell.answers(declared(variable), value);
    });
    return machine;
  }

  /// The spec of the pool the step wrote.
  Map<String, Object?> writtenSpec(ClusterMachine machine) {
    final Map<String, Object?> pool =
        jsonDecode(machine.files.contents[poolPath]!) as Map<String, Object?>;
    expect(pool['apiVersion'], 'crd.projectcalico.org/v1');
    expect(pool['kind'], 'IPPool');
    expect((pool['metadata']! as Map<String, Object?>)['name'], 'pod-cidr-ipv4-ippool');
    return pool['spec']! as Map<String, Object?>;
  }

  test(
    'a cluster on the default range gets the pool the agent would build, on the new range',
    () async {
      // The setting the shipped manifest of this cluster declares, and nothing else: every other
      // value is the one the agent gives a pool where its set declares none.
      final ClusterMachine machine = onTheDefaultRange(
        environment: <String, String>{'CALICO_IPV4POOL_VXLAN': 'Always'},
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(writtenSpec(machine), <String, Object?>{
        'cidr': podCidr,
        'blockSize': 26,
        'ipipMode': 'Never',
        'vxlanMode': 'Always',
        'natOutgoing': true,
        'disableBGPExport': false,
        'nodeSelector': 'all()',
        'allowedUses': <String>['Workload', 'Tunnel'],
      });
      expect(machine.changing, contains(applyPool));
      expect(
        machine.changing.where((String each) => each.contains('delete')),
        isEmpty,
        reason: 'the default pool is the next row\'s to delete, once this one stands',
      );
    },
  );

  test('a second run finds the pool standing and does nothing', () async {
    final ClusterMachine machine = onTheDefaultRange();
    final StepContext context = machine.contextFor(under);
    await step.apply(context);

    expect(await step.check(context), isA<Satisfied>());
  });

  test('THE INNOCENT NEIGHBOUR: a cluster converted before is left alone', () async {
    // Its default pool already carries the range. A second pool over the same range is one Calico's
    // address management is not built for.
    final ClusterMachine machine = ClusterMachine()
      ..shell.answers(pools, 'default-ipv4-ippool=$podCidr\n');

    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
    expect(machine.files.contents.containsKey(poolPath), isFalse);
  });

  test('the settings the agent is set up with are the settings the pool gets', () async {
    final ClusterMachine machine = onTheDefaultRange(
      environment: <String, String>{
        'CALICO_IPV4POOL_IPIP': 'CrossSubnet',
        'CALICO_IPV4POOL_VXLAN': 'never',
        'CALICO_IPV4POOL_BLOCK_SIZE': '24',
        'CALICO_IPV4POOL_NAT_OUTGOING': 'no',
        'CALICO_IPV4POOL_DISABLE_BGP_EXPORT': 'true',
        'CALICO_IPV4POOL_NODE_SELECTOR': 'kubernetes.io/os == "linux"',
      },
    );
    await step.apply(machine.contextFor(under));

    expect(writtenSpec(machine), <String, Object?>{
      'cidr': podCidr,
      'blockSize': 24,
      'ipipMode': 'CrossSubnet',
      'vxlanMode': 'Never',
      'natOutgoing': false,
      'disableBGPExport': true,
      'nodeSelector': 'kubernetes.io/os == "linux"',
      'allowedUses': <String>['Workload', 'Tunnel'],
    });
  });

  test('a setting the agent would refuse to start with is refused here too', () async {
    final ClusterMachine machine = onTheDefaultRange(
      environment: <String, String>{
        'CALICO_IPV4POOL_VXLAN': 'sometimes',
        'CALICO_IPV4POOL_BLOCK_SIZE': '40',
      },
    );

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('CALICO_IPV4POOL_VXLAN="sometimes"'));
    expect(answer.reason, contains('CALICO_IPV4POOL_BLOCK_SIZE="40"'));
  });

  test('an agent set that cannot be read is refused, never read as declaring nothing', () async {
    final ClusterMachine machine = onTheDefaultRange()
      ..shell.fails(declared('CALICO_IPV4POOL_IPIP'), stderr: 'the server is currently unable');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('calico-node'));
    expect(machine.changing, isEmpty);
  });

  test('a cluster that cannot list its pools is refused, never read as holding none', () async {
    final ClusterMachine machine = ClusterMachine()
      ..cannotBeReached('ippool', stderr: 'connection refused');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('would not list its address pools'));
    expect(machine.changing, isEmpty);
  });

  test('the pool standing on another range is not moved to this one', () async {
    final ClusterMachine machine = ClusterMachine()
      ..shell.answers(pools, '${CreateIpv4IppoolForPodCidr.poolName}=10.10.0.0/16\n');

    final CheckResult answer = await step.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('stands on 10.10.0.0/16'));
    expect(machine.changing, isEmpty);
  });

  test('it cannot be taken back, because the pods that took an address would be stranded', () {
    expect(step, isA<IrreversibleStep>());
    expect(step.irreversibleReason, contains('stranding'));
  });
}
