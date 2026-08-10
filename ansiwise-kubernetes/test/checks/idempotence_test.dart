import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [kubernetesRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  kubernetesRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// `kubectl apply`, `kubectl patch` or `kubectl delete` would leave behind never sees it become
/// true; a step whose precondition is a running cluster is blocked before it starts. Neither is a
/// defect in the step, and neither is evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{
  'align_calico_backend',
  'apply_cluster_issuer',
  'delete_default_ipv4_ippool',
  'delete_existing_cluster_issuer',
  // Its postcondition is a ConfigMap composed from a directory, and composing it is a kubectl call
  // whose OUTPUT the step then applies — a fake shell answers a command, it does not compose one.
  'kubernetes_configmap_from_directory',
  'kubernetes_namespace',
  'oidc_admins_binding',
  // Both leave their postcondition behind with a kubectl call: the value of a key and the pods of a
  // workload are read back out of the cluster, and a fake shell answers a command rather than
  // carrying it out. Named here rather than counted as passing.
  'patch_configmap_key',
  'patch_container_arguments_and_ports',
  'reapply_calico_manifest',
  'recycle_kube_system_pod_ips',
  'restart_cert_manager_and_reapply_cluster_issuer',
  'set_default_storage_class',
  'verify_ippool_converged_with_self_heal',
};
