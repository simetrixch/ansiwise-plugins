import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The whole of `deploy-cluster`, run against a machine that exists only in memory.
///
/// The machine here is one the program has already converged: every step of it answers that there
/// is nothing to do. That is the double-run test the whole framework rests on, and it is the one
/// property this program cannot be trusted without — a machine serving traffic reaches this code by
/// an ordinary re-run, and a step that did its work again there would swap the address pool
/// underneath every workload on it.
void main() {
  ResolvedProgram deployCluster() => const ProgramResolver(executionRegistry).resolve(
    loadProgram(
      File('programs/deploy-cluster.yaml').readAsStringSync(),
      where: 'deploy-cluster.yaml',
    ),
  );

  Program declared() => loadProgram(
    File('programs/deploy-cluster.yaml').readAsStringSync(),
    where: 'deploy-cluster.yaml',
  );

  /// What an operator supplies, put through the program's OWN declaration.
  ///
  /// Validated rather than handed straight to the runner, so this fixture cannot drift from what
  /// `deploy-cluster.yaml` asks for: an answer the program stopped declaring, or a required one
  /// nobody gave, fails here instead of leaving a step reading an empty bag.
  Arguments answered() => declared().answers.validate(<String, Object?>{
    ...clusterAnswerValues,
  }, program: 'deploy-cluster');

  RunRecord header(Mode mode, FakeClock clock) => RunRecord(
    id: const RunId('20260807T120000Z-1'),
    program: const ProgramName('deploy-cluster'),
    mode: mode,
    argv: const <String>['ansiwise', 'deploy-cluster'],
    start: clock.now(),
    stage: const Stage('dev'),
    role: const Role('master'),
    fqdn: const Fqdn('m1.example.com'),
    commit: 'abc1234',
    fingerprint: 'f',
  );

  Future<({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder})> run(
    Mode mode, {
    ClusterMachine? machine,
  }) async {
    final ClusterMachine it = machine ?? convergedCluster();
    final MemoryRecorder recorder = MemoryRecorder(it.clock);
    final RunRecord record =
        await Runner(
          machine: Machine(
            shell: it.shell,
            files: it.files,
            http: FakeHttp(),
            clock: it.clock,
            entropy: FakeEntropy(),
          ),
          recorder: recorder,
          redactor: Redactor.none,
        ).run(
          program: deployCluster(),
          mode: mode,
          header: header(mode, it.clock),
          answers: answered(),
        );
    return (record: record, shell: it.shell, files: it.files, recorder: recorder);
  }

  test('the program resolves against the registry', () {
    expect(deployCluster().steps, hasLength(59));
  });

  test('every value this installation states about itself is an answer, not an argument', () {
    // The defect this replaces: the domain, the stage, the account, the mailbox and the storage
    // paths stood in this file as step arguments with one installation's value for each. A program
    // file ships to every installation, so this cluster would have asked a certificate authority
    // for a domain it does not answer at and pointed its dashboard at somebody else's identity
    // provider.
    //
    // The names are listed rather than allow-listed the other way round: this file carries some
    // forty argument names that ARE the platform's own decisions — the pod range, the addon list,
    // the pinned tool versions — and a list of those would go stale on every step added.
    const List<String> namesOneInstallationOwns = <String>[
      'stage',
      'role',
      'user',
      'domain_suffix',
      'build_plane_fqdn',
      'issuer_url',
      'contact_email',
      'lan_cidr',
      'storage_path',
      'storage_directory',
    ];

    expect(
      <String>[for (final ArgumentSpec spec in declared().answers.specs) spec.name],
      containsAll(<String>[
        'fqdn',
        'stage',
        'role',
        'operator_user',
        'letsencrypt_email',
        'lan_cidr',
        'storage_path',
        'storage_directory',
      ]),
    );

    for (final ResolvedStep step in deployCluster().steps) {
      for (final String name in step.entry.arguments.names) {
        expect(
          namesOneInstallationOwns,
          isNot(contains(name)),
          reason:
              '${step.entry.step} is given "$name" in the program file, and that names one '
              'installation — it belongs in the answers block at the end of the file',
        );
      }
    }
  });

  test('every step of it is registered under the name the file writes', () {
    for (final ResolvedStep step in deployCluster().steps) {
      expect(
        executionRegistry.step(step.entry.step),
        isNotNull,
        reason: '${step.entry.step} is in the program and not in the registry',
      );
    }
  });

  group('--mode dry', () {
    test('changes nothing on the machine', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(it.files.directories, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes).map((Command c) => c.argv.join(' ')),
        isEmpty,
        reason: 'a dry run may only run commands a step declared as observing',
      );
    });

    test('every step comes back green', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);
      expect(it.record.exitCode, 0);
      for (final StepRecord step in it.record.steps) {
        expect(step.verdict, isA<Succeeded>(), reason: '${step.step} was not green');
      }
    });

    test('it plans nothing at all, because the machine is already converged', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);
      for (final StepRecord step in it.record.steps) {
        expect(
          step.plan,
          isA<NothingPlan>(),
          reason:
              '${step.step} planned work on a converged '
              'machine',
        );
      }
    });
  });

  group('--mode test', () {
    test('it measures the machine and does no work', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.test);

      expect(it.record.exitCode, 0);
      expect(it.files.written, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a test run does no work',
      );
    });
  });

  group('--mode run', () {
    test('a second run of the whole program changes nothing', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(it.record.exitCode, 0);
      expect(it.files.written, isEmpty, reason: 'a converged machine is written to by nothing');
      expect(it.files.deleted, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes).map((Command c) => c.argv.join(' ')),
        isEmpty,
        reason: 'a converged machine has no command run against it that changes anything',
      );
      for (final StepRecord step in it.record.steps) {
        expect(step.verdict, isA<Succeeded>(), reason: '${step.step} was not green');
      }
    });

    test('a pod network that overlaps the fixed service range is refused', () async {
      // Nothing is installed onto a machine whose pod range would make its pods unable to reach the
      // API server, and the refusal comes before the conversion touches anything.
      final ClusterMachine machine = convergedCluster();
      final ResolvedProgram program = deployCluster();
      final ResolvedStep gate = program.steps.firstWhere(
        (ResolvedStep s) =>
            s.entry.step == const StepName('require_pod_cidr_free_of_reserved_ranges'),
      );

      const RequirePodCidrFreeOfReservedRanges refused = RequirePodCidrFreeOfReservedRanges(
        podCidr: '10.152.183.0/24',
        serviceCidr: '10.152.183.0/24',
      );
      final CheckResult answer = await refused.check(machine.contextFor(gate.entry.step));
      expect((answer as Blocked).reason, contains('10.152.183.0/24'));
    });
  });

  group('the order the file writes is the order the failures need', () {
    List<StepName> order() => <StepName>[
      for (final ResolvedStep s in deployCluster().steps) s.entry.step,
    ];

    void before(String earlier, String later, String why) {
      final List<StepName> steps = order();
      expect(
        steps.indexOf(StepName(earlier)),
        lessThan(steps.indexOf(StepName(later))),
        reason: why,
      );
    }

    test('the packet-filtering backend is set before any addon is switched on', () {
      before(
        'configure_kube_proxy_nftables',
        'enable_addons',
        'set afterwards, rules already exist in the other backend and nothing here removes them',
      );
    });

    test('the pod network is converted before any addon can be given an address out of it', () {
      before(
        'recycle_kube_system_pod_ips',
        'enable_addons',
        'converted later, every workload on the machine has to be given a new address',
      );
    });

    test('the image mirror is written before the first image is pulled', () {
      before(
        'write_containerd_docker_mirror',
        'enable_addons',
        "written later, the bring-up spends the public registry's allowance",
      );
    });

    test('the seven steps of the conversion are in the order they have to be in', () {
      final List<StepName> steps = order();
      final List<String> conversion = <String>[
        'stamp_calico_pool_cidr_in_cni_manifest',
        'stamp_kube_proxy_cluster_cidr',
        'delete_default_ipv4_ippool',
        'reapply_calico_manifest',
        'restart_microk8s_snap_for_pod_cidr',
        'verify_ippool_converged_with_self_heal',
        'recycle_kube_system_pod_ips',
      ];
      final List<int> positions = <int>[
        for (final String step in conversion) steps.indexOf(StepName(step)),
      ];
      expect(positions, everyElement(isNot(-1)));
      for (int i = 1; i < positions.length; i++) {
        expect(
          positions[i - 1],
          lessThan(positions[i]),
          reason: '${conversion[i - 1]} has to come before ${conversion[i]}',
        );
      }
    });

    test('the guard against a populated cluster comes before the first step of the conversion', () {
      before(
        'guard_populated_cluster_pod_cidr_migration',
        'stamp_calico_pool_cidr_in_cni_manifest',
        'a guard that runs after the swap has nothing left to protect',
      );
    });

    test('the addons that must be off are switched off after the ones that must be on go on', () {
      before(
        'enable_addons',
        'disable_addons',
        'some addons come on by themselves when the snap installs',
      );
    });

    test('what an addon installed is patched only after the addon is up', () {
      for (final String patch in <String>[
        'patch_coredns_corefile',
        'align_calico_backend',
        'patch_traefik_cross_namespace',
      ]) {
        before(
          'enable_addons',
          patch,
          'the object $patch changes only exists once the addon is up',
        );
      }
    });

    test('the running ingress pod is compared only after its declaration was patched', () {
      before(
        'patch_traefik_cross_namespace',
        'force_roll_traefik_daemonset',
        'the comparison exists because patching the declaration does not reach the running pod',
      );
    });

    test('the drop-in is proved to have merged before the configuration is applied', () {
      before(
        'assert_netplan_merged',
        'apply_netplan',
        "applying a drop-in that did not merge takes the interface's address configuration away",
      );
    });

    test('the structured-text reader is installed before anything reads structured output', () {
      before(
        'install_jq',
        'install_argocd_cli',
        'later logic in the same run reads structured output with it',
      );
    });

    test('the pins are held against the machine last, after every tool step', () {
      final List<StepName> steps = order();
      for (final String tool in <String>[
        'install_jq',
        'install_argocd_cli',
        'install_vault_cli',
        'install_yq_cli',
        'install_tailscale_client',
      ]) {
        expect(
          steps.indexOf(StepName(tool)),
          lessThan(steps.indexOf(const StepName('assert_cli_tool_versions'))),
          reason: 'the assertion is the only thing binding the list of tools to the steps',
        );
      }
    });
  });

  test('the ten points beyond which there is no going back are named', () {
    // The dry run names these in advance, which it can only do because each of them says so about
    // itself. A step moved out of this list is a point of no return the operator is not told about.
    const List<String> irreversible = <String>[
      'remove_microk8s_snap_forced',
      'install_microk8s_snap',
      'delete_default_ipv4_ippool',
      'verify_ippool_converged_with_self_heal',
      'recycle_kube_system_pod_ips',
      'apply_netplan',
      'create_storage_directory',
      'link_microk8s_storage_path',
      'export_kubeconfig',
      'force_roll_traefik_daemonset',
    ];
    for (final String name in irreversible) {
      final RegisteredStep? entry = executionRegistry.step(StepName(name));
      expect(entry, isNotNull, reason: '$name is not registered');
      final Step step = entry!.create(_plausible(entry.arguments));
      expect(step, isA<IrreversibleStep>(), reason: '$name is a point of no return');
      final String reason = (step as IrreversibleStep).irreversibleReason;
      expect(
        reason.split(' ').length,
        greaterThan(8),
        reason: '$name says nothing about what is lost',
      );
      expect(
        reason.toLowerCase(),
        isNot(anyOf(contains('not implemented'), contains('no undo'))),
        reason: '$name says no undo was written rather than what cannot be reversed',
      );
    }
  });

  test('no customer domain reaches the program file', () {
    final String text = File('programs/deploy-cluster.yaml').readAsStringSync();
    expect(text, isNot(contains('digitacloud.app')));
    expect(text, isNot(contains('digitaplatform.com')));
  });
}

/// A value for every argument, so a registered step can be built outside a run.
Arguments _plausible(List<ArgumentSpec> specs) => Arguments(<String, Object>{
  for (final ArgumentSpec spec in specs)
    spec.name:
        spec.defaultValue ??
        switch (spec.kind) {
          ArgumentKind.text => 'x',
          ArgumentKind.integer => 1,
          ArgumentKind.flag => false,
          ArgumentKind.textList => const <String>['x'],
        },
});
