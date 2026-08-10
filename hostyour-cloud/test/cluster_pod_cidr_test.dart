import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The conversion of the pod network, and every way it was found to converge to a wrong-looking
/// right state.
void main() {
  const StepName under = StepName('under_test');

  /// A run on a machine that shares [lan] with the other clusters, or none where [lan] is empty.
  StepContext onALan(String lan) => ClusterMachine().contextFor(
    under,
    Arguments.none,
    clusterAnswering(<String, Object>{'lan_cidr': lan}),
  );

  const String manifestPath = StampCalicoPoolCidrInCniManifest.defaultPath;
  const String argsPath = microk8sKubeProxyArguments;
  const String livePool =
      'microk8s kubectl get ippool default-ipv4-ippool -o jsonpath={.spec.cidr}';
  const String podsEverywhere =
      r'microk8s kubectl get pods --all-namespaces -o '
      r'jsonpath={range .items[*]}{.metadata.namespace}{" "}{.metadata.name}{" "}'
      r'{.spec.hostNetwork}{"\n"}{end}';
  const String systemPods =
      r'microk8s kubectl -n kube-system get pods -o '
      r'jsonpath={range .items[*]}{.metadata.name}{" "}{.spec.hostNetwork}{" "}'
      r'{.status.podIP}{"\n"}{end}';

  group('the ranges a pod network may not overlap', () {
    test('two ranges overlap under the SHORTER of the two prefixes', () {
      // The obvious implementation gets containment right in one direction and wrong in the other.
      expect(RequirePodCidrFreeOfReservedRanges.overlap('10.1.0.0/16', '10.1.1.0/24'), isTrue);
      expect(RequirePodCidrFreeOfReservedRanges.overlap('10.1.1.0/24', '10.1.0.0/16'), isTrue);
      expect(RequirePodCidrFreeOfReservedRanges.overlap('10.244.0.0/16', '10.1.0.0/16'), isFalse);
    });

    test('a zero-length prefix overlaps everything', () {
      // The arithmetic is done wide and masked back to 32 bits at the end. A 32-bit implementation
      // overflows here and answers the opposite.
      expect(RequirePodCidrFreeOfReservedRanges.overlap('0.0.0.0/0', '10.244.0.0/16'), isTrue);
      expect(RequirePodCidrFreeOfReservedRanges.overlap('192.168.1.0/24', '0.0.0.0/0'), isTrue);
    });

    test("the fixed range MicroK8s hands cluster IPs out of is refused, and it is not "
        'configurable', () async {
      const RequirePodCidrFreeOfReservedRanges gate = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.152.0.0/16',
        serviceCidr: '10.152.183.0/24',
      );
      final CheckResult answer = await gate.check(ClusterMachine().contextFor(under));
      expect((answer as Blocked).reason, contains('10.152.183.0/24'));
    });

    test('a LAN that overlaps is refused, and no LAN skips that half', () async {
      const RequirePodCidrFreeOfReservedRanges overlapping = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.1.0.0/16',
        serviceCidr: '10.152.183.0/24',
      );
      final CheckResult refused = await overlapping.check(onALan('10.1.1.0/24'));
      expect((refused as Blocked).reason, contains('10.1.1.0/24'));

      const RequirePodCidrFreeOfReservedRanges unset = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.1.0.0/16',
        serviceCidr: '10.152.183.0/24',
      );
      expect(await unset.check(ClusterMachine().contextFor(under)), isA<Satisfied>());
    });

    test('everything wrong is reported at once', () async {
      const RequirePodCidrFreeOfReservedRanges gate = RequirePodCidrFreeOfReservedRanges(
        podCidr: 'not-a-range',
        serviceCidr: 'also-not',
      );
      final CheckResult answer = await gate.check(onALan('nor-this'));
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
      const GuardPopulatedClusterPodCidrMigration guard = GuardPopulatedClusterPodCidrMigration(
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

      const GuardPopulatedClusterPodCidrMigration guard = GuardPopulatedClusterPodCidrMigration(
        podCidr: podCidr,
        argsPath: argsPath,
        allowPopulatedMigration: false,
      );
      expect(await guard.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('the override lets it through and says every pod has to be restarted', () async {
      final ClusterMachine machine = populated(liveCidr: '10.1.0.0/16');
      const GuardPopulatedClusterPodCidrMigration guard = GuardPopulatedClusterPodCidrMigration(
        podCidr: podCidr,
        argsPath: argsPath,
        allowPopulatedMigration: true,
      );

      expect(await guard.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.said.join('\n'), contains('restarted by hand'));
    });

    test('a cluster that already runs on the range is not guarded, there being no swap', () async {
      final ClusterMachine machine = populated(liveCidr: podCidr, converged: true);
      const GuardPopulatedClusterPodCidrMigration guard = GuardPopulatedClusterPodCidrMigration(
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

      const GuardPopulatedClusterPodCidrMigration guard = GuardPopulatedClusterPodCidrMigration(
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

  group('the stamp into the network manifest', () {
    test('the value on the line FOLLOWING the variable is what changes', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.files.contents[manifestPath], contains('value: "$podCidr"'));
      expect(machine.files.contents[manifestPath], isNot(contains('10.1.0.0/16')));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the value of another variable on the same manifest is untouched', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      await step.apply(machine.contextFor(under));
      expect(machine.files.contents[manifestPath], contains('value: "Never"'));
    });

    test('a manifest carrying no such variable is refused rather than reported as done', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = 'kind: DaemonSet\nspec: {}\n';

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('CALICO_IPV4POOL_CIDR'));
    });

    test('a rewrite that quietly did nothing fails rather than reporting success', () async {
      // The failure an exit code cannot see: the write ran, returned zero and changed nothing.
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      await expectLater(
        step.apply(
          StepContext(
            shell: machine.shell,
            files: _SwallowingFiles(machine.files),
            http: FakeHttp(),
            clock: machine.clock,
            entropy: FakeEntropy(),
            log: _SilentLog(machine.said),
            step: under,
            arguments: Arguments.none,
            facts: Facts.none,
          ),
        ),
        throwsA(isA<CommandFailed>()),
      );
    });

    test('a second run writes nothing and leaves no new copy behind', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = cniManifest(cidr: '10.1.0.0/16');

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final StepContext context = machine.contextFor(under);

      await step.apply(context);
      final int backupsAfterOne = machine.files.contents.keys
          .where((String path) => path.contains('.bak.'))
          .length;
      machine.files.written.clear();

      expect(await step.check(context), isA<Satisfied>());
      await step.apply(context);
      expect(machine.files.written, isEmpty);
      expect(
        machine.files.contents.keys.where((String path) => path.contains('.bak.')).length,
        backupsAfterOne,
      );
    });

    test('the copy taken before the change is what an undo puts back', () async {
      final ClusterMachine machine = ClusterMachine();
      final String before = cniManifest(cidr: '10.1.0.0/16');
      machine.files.contents[manifestPath] = before;

      const StampCalicoPoolCidrInCniManifest step = StampCalicoPoolCidrInCniManifest(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final StepContext context = machine.contextFor(under);
      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);
      expect(machine.files.contents[manifestPath], before);
    });
  });

  group("the stamp into the service proxy's arguments", () {
    // The row `deploy-cluster` writes. kube-proxy decides what counts as leaving the pod network
    // from this one line: carrying the old range it translates the wrong traffic and leaves the
    // right traffic untranslated, which shows up as pods that reach some addresses and not others.
    const SetProcessFlag clusterCidr = SetProcessFlag(
      argsPath: argsPath,
      flag: GuardPopulatedClusterPodCidrMigration.clusterCidrFlag,
      value: podCidr,
    );

    test('an existing line is replaced in place rather than a second one appended', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n--cluster-cidr=10.1.0.0/16\n';

      const SetProcessFlag step = clusterCidr;
      final StepContext context = machine.contextFor(under);
      await step.apply(context);

      final List<String> lines = machine.files.contents[argsPath]!.split('\n');
      expect(lines.where((String each) => each.startsWith('--cluster-cidr=')), hasLength(1));
      expect(machine.files.contents[argsPath], contains('--cluster-cidr=$podCidr'));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a file carrying none gains the line at the end', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--proxy-mode=nftables\n';

      const SetProcessFlag step = clusterCidr;
      await step.apply(machine.contextFor(under));
      expect(machine.files.contents[argsPath], '--proxy-mode=nftables\n--cluster-cidr=$podCidr\n');
    });

    test('the service that reads it is the one that is restarted', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '';

      const SetProcessFlag step = clusterCidr;
      await step.apply(machine.contextFor(under));
      expect(
        machine.changing,
        contains('snap restart $microk8sKubelite'),
        reason: 'the service proxy is not a process of its own',
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
        ..changes('microk8s kubectl delete ippool default-ipv4-ippool', () {
          machine.shell.fails(livePool);
        });
      machine.files.contents[manifestPath] = cniManifest();

      const DeleteDefaultIpv4Ippool step = DeleteDefaultIpv4Ippool(
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

      const DeleteDefaultIpv4Ippool step = DeleteDefaultIpv4Ippool(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('straight back on 10.1.0.0/16'));
      expect(machine.changing, isEmpty);
    });

    test('a pool already on the range is left alone', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(livePool, podCidr);
      const DeleteDefaultIpv4Ippool step = DeleteDefaultIpv4Ippool(
        podCidr: podCidr,
        manifestPath: manifestPath,
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });

  group('the verify, and the race it answers', () {
    const String rollAgent =
        'microk8s kubectl -n kube-system rollout restart daemonset/calico-node';

    test(
      'a pool that came back on the old range is deleted once more and the agent replaced',
      () async {
        // Measured on a fresh install: the first look found no pool, so the delete was skipped, and
        // the agent that was already running created it from its OLD environment before the restart
        // handed it the new one.
        final ClusterMachine machine = ClusterMachine();
        machine.shell
          ..answers(livePool, '10.1.0.0/16')
          ..changes('microk8s kubectl delete ippool default-ipv4-ippool', () {
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
        expect(machine.changing, contains('microk8s kubectl delete ippool default-ipv4-ippool'));
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
          (String each) => each == 'microk8s kubectl delete ippool default-ipv4-ippool',
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
      machine.shell.changes(
        'microk8s kubectl -n kube-system delete pod calico-kube-controllers-def --wait=false',
        () {},
      );

      const RecycleKubeSystemPodIps step = RecycleKubeSystemPodIps(podCidr: podCidr);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.changing, <String>[
        'microk8s kubectl -n kube-system delete pod calico-kube-controllers-def --wait=false',
        'microk8s kubectl -n kube-system delete pod coredns-ghi --wait=false',
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

/// A file system that answers every read and drops every write.
final class _SwallowingFiles implements Files {
  const _SwallowingFiles(this.inner);

  final Files inner;

  @override
  Future<bool> exists(String path) => inner.exists(path);

  @override
  Future<String> read(String path) => inner.read(path);

  @override
  Future<List<String>> list(String path) => inner.list(path);

  @override
  Future<void> write(String path, String content, {required int mode}) async {}

  @override
  Future<void> delete(String path) async {}

  @override
  Future<void> createDirectory(String path, {required int mode}) async {}
}

final class _SilentLog implements Logger {
  const _SilentLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}
