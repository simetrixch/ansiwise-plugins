import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

import 'step_fixtures.dart';

Future<void> main() async {
  final Idempotence check = Idempotence(
    registry: executionRegistry,
    answers: await plausibleAnswers(const RealFiles(), 'programs'),
    fixtures: stepFixtures,
  );
  final IdempotenceReading reading = await check.runEveryStep();

  test('every registered step was run twice', () {
    expect(
      reading.coverage,
      hasLength(executionRegistry.steps.length),
      reason: 'some step was never run, so nothing about its second run was measured',
    );
  });

  test('no registered step was seen to do its work twice', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          "the shape is exact: the step's check answers Satisfied the second time, before any work, "
          'so the engine never calls apply again',
    );
  });

  test('${reading.exercisedNames.length} step(s) were applied against a fake machine and were '
      'satisfied afterwards', () {
    expect(
      reading.exercisedNames,
      isNotEmpty,
      reason:
          'not one step got from having work to having none, so the fixtures in step_fixtures.dart '
          'no longer arrange the fake machine for anything',
    );
  });

  test('${reading.observingNames.length} step(s) only measure and answered the same twice', () {
    expect(
      reading.observingNames,
      isNotEmpty,
      reason: 'no observing step was recognised as one, so that bucket measured nothing',
    );
  });

  test(
    '${reading.notCoveredNames.length} step(s) are NOT COVERED, and they are exactly the ones named '
    'in this file',
    () {
      // A skip is not silent and it is not a pass. Naming them in a ledger the check asserts against
      // is what makes a step added tomorrow bring its fixture or force somebody to write its name
      // here — and what makes a fixture that stopped working turn the gate red instead of quietly
      // moving one more step into this list.
      expect(
        reading.notCoveredNames,
        orderedEquals(notCoveredByAFakeMachine.toList()..sort()),
        reason:
            'a step a fake machine cannot exercise has not been shown to be idempotent by anything; '
            'either arrange the fake for it in step_fixtures.dart, or name it here',
      );
    },
  );

  group('counter-probe', () {
    // Three steps written here, run through the same machinery. The third is the one this whole
    // check is shaped around: a step whose work is left behind by a command must come back NOT
    // COVERED and never exercised — because a fake shell answers every command the same way before
    // and after, so its check would answer the same both times for a reason that has nothing to do
    // with the step being idempotent. Collapse the two into one and this is what says so.

    test('a step that would work twice is caught', () async {
      expect(
        await _runTwice(const DoesItsWorkEveryTime()),
        isA<WouldRepeat>(),
        reason: 'a step planted here writes on every run and its check never notices',
      );
    });

    test('a step whose second run is a no-op is exercised', () async {
      expect(
        await _runTwice(const WritesOnlyOnce()),
        isA<Exercised>(),
        reason: 'a step planted here writes once and is satisfied afterwards',
      );
    });

    test('a step the fake machine cannot exercise is not counted as passing', () async {
      expect(
        await _runTwice(const WorksThroughACommand()),
        isA<NotCovered>(),
        reason:
            'a step planted here leaves its postcondition behind with a command the fake shell does '
            'not carry out, and counting that as a pass is the failure this check exists to prevent',
      );
    });

    test('a fixture that carries the command out makes the same step measurable', () async {
      // The other half of the third: with the fake arranged the way a real machine would be, the
      // same step IS exercised. Without this, a check that answered NOT COVERED to everything would
      // pass the test above.
      expect(
        await _runTwice(
          const WorksThroughACommand(),
          fixture: (FakeShell shell, FakeFiles files, FakeHttp http) {
            shell.changes('touch ${WorksThroughACommand.path}', () {
              shell.answers('test -e ${WorksThroughACommand.path}', 'there');
            });
          },
        ),
        isA<Exercised>(),
        reason: 'FakeShell.changes is what lets a postcondition actually become true',
      );
    });
  });
}

Future<Coverage> _runTwice(Step step, {Fixture? fixture}) =>
    runTwice(const StepName('planted'), step, Arguments.none, fixture: fixture);

/// Where the planted steps write, so the three of them cannot read each other's file.
const String _plantedPath = '/etc/planted';

/// A step that writes every time it is run and never notices that it has.
final class DoesItsWorkEveryTime extends ReversibleStep<bool> {
  /// Creates the planted step.
  const DoesItsWorkEveryTime();

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'again');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'again', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step that writes once and answers satisfied from then on.
final class WritesOnlyOnce extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WritesOnlyOnce();

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(_plantedPath)) {
      return const CheckResult.ready();
    }
    return await context.files.read(_plantedPath) == 'once'
        ? const CheckResult.satisfied('the file already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'once');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'once', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step whose postcondition a real command would leave behind, and a fake one never does.
final class WorksThroughACommand extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WorksThroughACommand();

  /// The marker the command leaves behind.
  static const String path = '/etc/planted-by-a-command';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there'
        ? const CheckResult.satisfied('the marker is there')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(<String>['touch', path]);

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(const Command('touch', <String>[path]));
  }

  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there';
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(const Command('rm', <String>['-f', path]));
  }
}

/// The steps a fake machine cannot exercise, each named because a check that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// `snap install`, `helm upgrade` or `kubectl apply` would leave behind never sees it become true;
/// a step whose precondition is a checkout, an account or a running cluster is blocked before it
/// starts. Neither is a defect in the step, and neither is evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{
  'activate_public_src_routing',
  'add_shell_alias',
  'add_user_to_group',
  'align_calico_backend',
  'apply_cluster_issuer',
  'apply_netplan',
  'argocd_root_app',
  'configure_kube_apiserver_oidc',
  'configure_kube_proxy_nftables',
  'configure_slave_apiserver_oidc_trust',
  'create_install_branch',
  'create_storage_directory',
  'delete_default_ipv4_ippool',
  'delete_existing_cluster_issuer',
  'disable_addons',
  'enable_addons',
  'ensure_tool_prerequisites',
  'export_kubeconfig',
  'helm_release',
  'helm_repository',
  'install_authorized_key',
  'install_pinned_tool',
  'install_snap',
  'install_tailscale_client',
  // Its postcondition is a ConfigMap composed from a directory, and composing it is a kubectl call
  // whose OUTPUT the step then applies — a fake shell answers a command, it does not compose one.
  'kubernetes_configmap_from_directory',
  'kubernetes_namespace',
  // Its postcondition is a Secret carrying what an entry of the secret store holds, so measuring it
  // needs an answer from that store — and a fixture arranges a fake shell and a fake file system,
  // not a scripted HTTP conversation. Named here rather than counted as passing.
  'kubernetes_secret_from_vault',
  'link_microk8s_storage_path',
  'oidc_admins_binding',
  // Both leave their postcondition behind with a kubectl call: the value of a key and the pods of a
  // workload are read back out of the cluster, and a fake shell answers a command rather than
  // carrying it out. Named here rather than counted as passing.
  'patch_configmap_key',
  'patch_container_arguments_and_ports',
  'reapply_calico_manifest',
  'recycle_kube_system_pod_ips',
  'remove_snap',
  'restart_cert_manager_and_reapply_cluster_issuer',
  'restart_microk8s_snap_for_pod_cidr',
  'set_default_storage_class',
  'stamp_calico_pool_cidr_in_cni_manifest',
  'stamp_fqdn',
  'stamp_kube_proxy_cluster_cidr',
  'stamp_revision',
  'stamp_role',
  'vault_auth_method',
  'vault_auth_role',
  'vault_init',
  'vault_kv_entry',
  'vault_kv_mount',
  'vault_policy',
  'vault_unsealed',
  'verify_ippool_converged_with_self_heal',
  'write_cluster_map',
  'write_connmark_nft_table',
  'write_containerd_docker_mirror',
  'write_netplan_public_src_routing',
  'write_public_src_routing_script',
  'write_public_src_routing_unit',
};
