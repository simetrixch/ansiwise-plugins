import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The conversion of the pod network, and every way it was found to converge to a wrong-looking
/// right state.
void main() {
  const StepName under = StepName('pod_cidr');
  const String podCidr = '10.244.0.0/16';
  const String serviceCidr = '10.152.183.0/24';
  const String manifestPath = '/etc/cni/cni.yaml';
  const String argsPath = '/etc/kube-proxy/args';
  const String livePool = 'kubectl get ippool default-ipv4-ippool -o jsonpath={.spec.cidr}';
  const String podsEverywhere =
      r'kubectl get pods --all-namespaces -o '
      r'jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}'
      r'{.spec.hostNetwork}{"\n"}{end}';
  const String systemPods =
      r'kubectl -n kube-system get pods -o '
      r'jsonpath={range .items[*]}{.metadata.name}{" "}{.spec.hostNetwork}{" "}'
      r'{.status.podIP}{"\n"}{end}';

  /// A network manifest whose pool range is [cidr], with the value on the line AFTER the name.
  String cniManifest({String cidr = podCidr}) =>
      'kind: DaemonSet\n'
      'spec:\n'
      '  template:\n'
      '    spec:\n'
      '      containers:\n'
      '        - name: calico-node\n'
      '          env:\n'
      '            - name: ${ReapplyCalicoManifest.variable}\n'
      '              value: "$cidr"\n';

  /// The service proxy's argument file once the range is on it.
  String kubeProxyArgs({String cidr = podCidr}) => '--cluster-cidr=$cidr\n';

  /// An answers bag that shares [lan] with the other machines, or none where it is empty.
  Arguments onALan(String lan) => Arguments(<String, Object>{'lan_cidr': lan});

  group('the ranges a pod network may not overlap', () {
    test('two ranges overlap under the SHORTER of the two prefixes', () {
      // The obvious implementation gets containment right in one direction and wrong in the other.
      expect(cidrOverlap('10.1.0.0/16', '10.1.1.0/24'), isTrue);
      expect(cidrOverlap('10.1.1.0/24', '10.1.0.0/16'), isTrue);
      expect(cidrOverlap('10.244.0.0/16', '10.1.0.0/16'), isFalse);
    });

    test('a zero-length prefix overlaps everything', () {
      // The arithmetic is done wide and masked back to 32 bits at the end. A 32-bit implementation
      // overflows here and answers the opposite.
      expect(cidrOverlap('0.0.0.0/0', '10.244.0.0/16'), isTrue);
      expect(cidrOverlap('192.168.1.0/24', '0.0.0.0/0'), isTrue);
    });

    test('the range the cluster hands service addresses out of is refused', () async {
      const RequirePodCidrFreeOfReservedRanges gate = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.152.0.0/16',
        serviceCidr: serviceCidr,
      );
      final CheckResult answer = await gate.check(
        ClusterMachine().contextFor(under, Arguments.none, onALan('')),
      );
      expect((answer as Blocked).reason, contains(serviceCidr));
    });

    test('a LAN that overlaps is refused, and no LAN skips that half', () async {
      const RequirePodCidrFreeOfReservedRanges overlapping = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.1.0.0/16',
        serviceCidr: serviceCidr,
      );
      final CheckResult refused = await overlapping.check(
        ClusterMachine().contextFor(under, Arguments.none, onALan('10.1.1.0/24')),
      );
      expect((refused as Blocked).reason, contains('10.1.1.0/24'));

      const RequirePodCidrFreeOfReservedRanges unset = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.1.0.0/16',
        serviceCidr: serviceCidr,
      );
      expect(
        await unset.check(ClusterMachine().contextFor(under, Arguments.none, onALan(''))),
        isA<Satisfied>(),
      );
    });

    test('everything wrong is reported at once', () async {
      const RequirePodCidrFreeOfReservedRanges gate = RequirePodCidrFreeOfReservedRanges(
        podCidr: 'not-a-range',
        serviceCidr: 'also-not',
      );
      final CheckResult answer = await gate.check(
        ClusterMachine().contextFor(under, Arguments.none, onALan('nor-this')),
      );
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('not-a-range'));
      expect(reason, contains('also-not'));
      expect(reason, contains('nor-this'));
    });
  });

  group('the hard guard against a cluster that carries workloads', () {
    ClusterMachine populated({required String liveCidr, bool converged = false}) {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(livePool, liveCidr)
        ..answers(
          podsEverywhere,
          'kube-system calico-node-abc true\n'
          'apps web-7f9 \n'
          'apps worker-2b1 \n',
        );
      machine.files.contents[argsPath] = kubeProxyArgs(cidr: converged ? podCidr : '10.1.0.0/16');
      return machine;
    }

    test('one pod outside the system namespace refuses the swap and names the override', () async {
      final ClusterMachine machine = populated(liveCidr: '10.1.0.0/16');
      const RequireUnpopulatedClusterForPodCidrMigration guard =
          RequireUnpopulatedClusterForPodCidrMigration(
            podCidr: podCidr,
            argsPath: argsPath,
            allowPopulatedMigration: false,
          );

      final CheckResult answer = await guard.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('2 pod(s)'));
      expect(reason, contains('allow_populated_migration'));
      expect(reason, contains('apps/web-7f9'));
      expect(machine.changing, isEmpty, reason: 'nothing is deleted by a guard that refused');
    });

    test('a pod on the host\'s own network is not counted, because the swap misses it', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(livePool, '10.1.0.0/16')
        ..answers(podsEverywhere, 'monitoring node-exporter-9 true\n');
      machine.files.contents[argsPath] = kubeProxyArgs(cidr: '10.1.0.0/16');

      const RequireUnpopulatedClusterForPodCidrMigration guard =
          RequireUnpopulatedClusterForPodCidrMigration(
            podCidr: podCidr,
            argsPath: argsPath,
            allowPopulatedMigration: false,
          );
      expect(await guard.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('the override lets it through and says every pod has to be restarted', () async {
      final ClusterMachine machine = populated(liveCidr: '10.1.0.0/16');
      const RequireUnpopulatedClusterForPodCidrMigration guard =
          RequireUnpopulatedClusterForPodCidrMigration(
            podCidr: podCidr,
            argsPath: argsPath,
            allowPopulatedMigration: true,
          );

      expect(await guard.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.said.join('\n'), contains('restarted by hand'));
    });

    test('a cluster that already runs on the range is not guarded, there being no swap', () async {
      final ClusterMachine machine = populated(liveCidr: podCidr, converged: true);
      const RequireUnpopulatedClusterForPodCidrMigration guard =
          RequireUnpopulatedClusterForPodCidrMigration(
            podCidr: podCidr,
            argsPath: argsPath,
            allowPopulatedMigration: false,
          );
      expect(await guard.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('convergence is read from the live pool and never from the manifest', () async {
      // A machine can carry a perfectly stamped manifest and run on the old pool: the manifest is
      // read once, when the pool is created.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(livePool, '10.1.0.0/16')
        ..answers(podsEverywhere, 'apps web-7f9 \n');
      machine.files.contents
        ..[argsPath] = kubeProxyArgs()
        ..[manifestPath] = cniManifest();

      const RequireUnpopulatedClusterForPodCidrMigration guard =
          RequireUnpopulatedClusterForPodCidrMigration(
            podCidr: podCidr,
            argsPath: argsPath,
            allowPopulatedMigration: false,
          );
      expect(
        await guard.check(machine.contextFor(under)),
        isA<Blocked>(),
        reason: 'the stamped manifest says nothing about the pool the cluster is running on',
      );
    });
  });

  group('the delete of the address pool', () {
    test('a pool the cluster is running on is deleted, which is the primary path', () async {
      // Even a machine installed minutes ago has a pool: the agent creates it from the shipped
      // manifest the first time it starts. Treating the delete as an edge case leaves a fresh
      // install on the shipped default.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(livePool, '10.1.0.0/16')
        ..changes('kubectl delete ippool default-ipv4-ippool', () {
          machine.shell.fails(livePool);
        });
      machine.files.contents[manifestPath] = cniManifest();

      const RemoveDefaultIpv4Ippool step = RemoveDefaultIpv4Ippool(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('deleting before the manifest carries the range is refused', () async {
      // Deleted first, the agent builds the pool straight back from a manifest that still names the
      // old range — and it never mutates a pool that exists.
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(livePool, '10.1.0.0/16');
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const RemoveDefaultIpv4Ippool step = RemoveDefaultIpv4Ippool(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('straight back on 10.1.0.0/16'));
      expect(machine.changing, isEmpty);
    });

    test('a pool already on the range is left alone', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(livePool, podCidr);
      const RemoveDefaultIpv4Ippool step = RemoveDefaultIpv4Ippool(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });

  group('the verify, and the race it answers', () {
    const String rollAgent = 'kubectl -n kube-system rollout restart daemonset/calico-node';

    test(
      'a pool that came back on the old range is deleted once more and the agent replaced',
      () async {
        // Measured on a fresh install: the first look found no pool, so the delete was skipped, and
        // the agent that was already running created it from its OLD environment before the restart
        // handed it the new one.
        final ClusterMachine machine = ClusterMachine();
        machine.shell
          ..answers(livePool, '10.1.0.0/16')
          ..changes('kubectl delete ippool default-ipv4-ippool', () {
            machine.shell.answers(livePool, podCidr);
          });

        const VerifyIppoolConvergedWithSelfHeal step = VerifyIppoolConvergedWithSelfHeal(
          podCidr: podCidr,
          timeoutSeconds: 180,
          intervalSeconds: 5,
          rolloutTimeoutSeconds: 120,
        );
        final StepContext context = machine.contextFor(under);

        expect(await step.check(context), isA<Ready>());
        await step.apply(context);
        expect(await step.check(context), isA<Satisfied>());
        expect(machine.changing, contains('kubectl delete ippool default-ipv4-ippool'));
        expect(machine.changing, contains(rollAgent));
        expect(machine.said.join('\n'), contains('came back covering 10.1.0.0/16'));
      },
    );

    test('the heal is taken once and no more', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(livePool, '10.1.0.0/16');

      const VerifyIppoolConvergedWithSelfHeal step = VerifyIppoolConvergedWithSelfHeal(
        podCidr: podCidr,
        timeoutSeconds: 30,
        intervalSeconds: 5,
        rolloutTimeoutSeconds: 120,
      );
      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<WaitedTooLong>()));
      expect(
        machine.changing.where(
          (String each) => each == 'kubectl delete ippool default-ipv4-ippool',
        ),
        hasLength(1),
        reason: 'a machine deleting a pool over and over against something it cannot fix',
      );
    });

    test('a pool that is not there yet is waited for and never healed', () async {
      // An empty read is Calico not having created the pool, and deleting nothing helps nothing.
      final ClusterMachine machine = ClusterMachine();
      machine.shell.fails(livePool);
      int looks = 0;
      machine.shell.changes(livePool, () {
        looks++;
        if (looks >= 3) {
          machine.shell.answers(livePool, podCidr);
        }
      });

      const VerifyIppoolConvergedWithSelfHeal step = VerifyIppoolConvergedWithSelfHeal(
        podCidr: podCidr,
        timeoutSeconds: 180,
        intervalSeconds: 5,
        rolloutTimeoutSeconds: 120,
      );
      await step.apply(machine.contextFor(under));
      expect(
        machine.changing.where((String each) => each.contains('delete ippool')),
        isEmpty,
        reason: 'there was no pool to delete',
      );
    });
  });

  group('the pods that came up before the swap', () {
    test('every one on the pod network is given a new address, and none on the host\'s', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(
        systemPods,
        'calico-node-abc true 10.1.1.10\n'
        'calico-kube-controllers-def  10.1.0.5\n'
        'coredns-ghi  10.1.0.6\n',
      );

      const RecycleKubeSystemPodIps step = RecycleKubeSystemPodIps(podCidr: podCidr);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.changing, <String>[
        // NOT `--wait=false`. The check right after this asks whether the pods still hold their old
        // addresses, and a client that returns on acceptance leaves them listed with exactly those
        // — measured at a hundred and seventy-nine milliseconds on a real machine, which reported a
        // step that ran and changed nothing.
        'kubectl -n kube-system delete pod calico-kube-controllers-def',
        'kubectl -n kube-system delete pod coredns-ghi',
      ]);
      expect(
        machine.changing.join('\n'),
        isNot(contains('calico-node-abc')),
        reason: "the network agent is on the host's own network and must not be touched",
      );
    });

    test(
      'a machine whose pods already hold addresses inside the range has nothing to do',
      () async {
        final ClusterMachine machine = ClusterMachine();
        machine.shell.answers(
          systemPods,
          'calico-node-abc true 10.1.1.10\ncalico-kube-controllers-def  10.244.0.5\n',
        );

        const RecycleKubeSystemPodIps step = RecycleKubeSystemPodIps(podCidr: podCidr);
        expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
        expect(machine.changing, isEmpty);
      },
    );
  });
}
