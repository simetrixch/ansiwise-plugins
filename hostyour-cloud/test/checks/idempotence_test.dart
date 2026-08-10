import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [executionRegistry], run twice against a fake machine.
///
/// The answers are every one the installation's programs declare, so each step meets the kind and
/// the default a real run would give it rather than a placeholder.
Future<void> main() async => auditIdempotence(
  executionRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
  answers: await plausibleAnswers(const RealFiles(), installationProgramsRoot),
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// `snap install`, `helm upgrade` or `kubectl apply` would leave behind never sees it become true; a
/// step whose precondition is a checkout, an account or a running cluster is blocked before it
/// starts. Neither is a defect in the step, and neither is evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{
  'argocd_root_app',
  'configure_kube_apiserver_oidc',
  'configure_slave_apiserver_oidc_trust',
  'create_install_branch',
  'disable_addons',
  'enable_addons',
  'kubernetes_secret_from_vault',
  'restart_microk8s_snap_for_pod_cidr',
  'stamp_calico_pool_cidr_in_cni_manifest',
  'stamp_placeholder_in_tracked_files',
  'stamp_role',
  'write_cluster_map',
  'write_containerd_docker_mirror',
};
