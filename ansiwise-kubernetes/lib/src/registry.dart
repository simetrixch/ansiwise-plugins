import 'package:ansiwise_core/ansiwise_core.dart';
import 'steps/align_calico_backend.dart';
import 'steps/align_calico_nat_port_range.dart';
import 'steps/apply_cluster_issuer.dart';
import 'steps/export_cluster_credentials.dart';
import 'steps/kubernetes_configmap_from_directory.dart';
import 'steps/kubernetes_namespace.dart';
import 'steps/kubernetes_object_irreversible.dart';
import 'steps/kubernetes_object_reversible.dart';
import 'steps/oidc_admins_binding.dart';
import 'steps/patch_configmap_key.dart';
import 'steps/patch_container_arguments_and_ports.dart';
import 'steps/reapply_calico_manifest.dart';
import 'steps/recycle_kube_system_pod_ips.dart';
import 'steps/remove_default_ipv4_ippool.dart';
import 'steps/remove_existing_cluster_issuer.dart';
import 'steps/remove_kubernetes_object.dart';
import 'steps/replace_calico_agent_for_pod_cidr.dart';
import 'steps/require_pod_cidr_free_of_reserved_ranges.dart';
import 'steps/require_unpopulated_cluster_for_pod_cidr_migration.dart';
import 'steps/restart_cert_manager_and_reapply_cluster_issuer.dart';
import 'steps/set_default_storage_class.dart';
import 'steps/verify_ippool_converged_with_self_heal.dart';
import 'steps/wait_for_command_output.dart';
import 'steps/write_cluster_issuer_manifest.dart';

/// The map from the names a program file writes to the classes that implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection. That is not a workaround
/// — it is what lets a check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> kubernetesSteps = <StepName, RegisteredStep>{
  StepName('wait_for_command_output'): RegisteredStep(
    name: StepName('wait_for_command_output'),
    source: 'lib/src/steps/wait_for_command_output.dart:33',
    create: WaitForCommandOutput.fromArguments,
    arguments: WaitForCommandOutput.arguments,
  ),
  StepName('require_pod_cidr_free_of_reserved_ranges'): RegisteredStep(
    name: StepName('require_pod_cidr_free_of_reserved_ranges'),
    source: 'lib/src/steps/require_pod_cidr_free_of_reserved_ranges.dart:19',
    create: RequirePodCidrFreeOfReservedRanges.fromArguments,
    arguments: RequirePodCidrFreeOfReservedRanges.arguments,
    answers: RequirePodCidrFreeOfReservedRanges.answers,
  ),
  StepName('require_unpopulated_cluster_for_pod_cidr_migration'): RegisteredStep(
    name: StepName('require_unpopulated_cluster_for_pod_cidr_migration'),
    source: 'lib/src/steps/require_unpopulated_cluster_for_pod_cidr_migration.dart:23',
    create: RequireUnpopulatedClusterForPodCidrMigration.fromArguments,
    arguments: RequireUnpopulatedClusterForPodCidrMigration.arguments,
  ),
  StepName('remove_default_ipv4_ippool'): RegisteredStep(
    name: StepName('remove_default_ipv4_ippool'),
    source: 'lib/src/steps/remove_default_ipv4_ippool.dart:16',
    create: RemoveDefaultIpv4Ippool.fromArguments,
    arguments: RemoveDefaultIpv4Ippool.arguments,
  ),
  StepName('reapply_calico_manifest'): RegisteredStep(
    name: StepName('reapply_calico_manifest'),
    source: 'lib/src/steps/reapply_calico_manifest.dart:14',
    create: ReapplyCalicoManifest.fromArguments,
    arguments: ReapplyCalicoManifest.arguments,
  ),
  StepName('replace_calico_agent_for_pod_cidr'): RegisteredStep(
    name: StepName('replace_calico_agent_for_pod_cidr'),
    source: 'lib/src/steps/replace_calico_agent_for_pod_cidr.dart:17',
    create: ReplaceCalicoAgentForPodCidr.fromArguments,
    arguments: ReplaceCalicoAgentForPodCidr.arguments,
  ),
  StepName('verify_ippool_converged_with_self_heal'): RegisteredStep(
    name: StepName('verify_ippool_converged_with_self_heal'),
    source: 'lib/src/steps/verify_ippool_converged_with_self_heal.dart:20',
    create: VerifyIppoolConvergedWithSelfHeal.fromArguments,
    arguments: VerifyIppoolConvergedWithSelfHeal.arguments,
  ),
  StepName('recycle_kube_system_pod_ips'): RegisteredStep(
    name: StepName('recycle_kube_system_pod_ips'),
    source: 'lib/src/steps/recycle_kube_system_pod_ips.dart:26',
    create: RecycleKubeSystemPodIps.fromArguments,
    arguments: RecycleKubeSystemPodIps.arguments,
  ),
  StepName('patch_configmap_key'): RegisteredStep(
    name: StepName('patch_configmap_key'),
    source: 'lib/src/steps/patch_configmap_key.dart:36',
    create: PatchConfigmapKey.fromArguments,
    arguments: PatchConfigmapKey.arguments,
  ),
  StepName('align_calico_backend'): RegisteredStep(
    name: StepName('align_calico_backend'),
    source: 'lib/src/steps/align_calico_backend.dart:51',
    create: AlignCalicoBackend.fromArguments,
    arguments: AlignCalicoBackend.arguments,
  ),
  StepName('align_calico_nat_port_range'): RegisteredStep(
    name: StepName('align_calico_nat_port_range'),
    source: 'lib/src/steps/align_calico_nat_port_range.dart:53',
    create: AlignCalicoNatPortRange.fromArguments,
    arguments: AlignCalicoNatPortRange.arguments,
  ),
  StepName('patch_container_arguments_and_ports'): RegisteredStep(
    name: StepName('patch_container_arguments_and_ports'),
    source: 'lib/src/steps/patch_container_arguments_and_ports.dart:46',
    create: PatchContainerArgumentsAndPorts.fromArguments,
    arguments: PatchContainerArgumentsAndPorts.arguments,
  ),
  StepName('set_default_storage_class'): RegisteredStep(
    name: StepName('set_default_storage_class'),
    source: 'lib/src/steps/set_default_storage_class.dart:24',
    create: SetDefaultStorageClass.fromArguments,
    arguments: SetDefaultStorageClass.arguments,
  ),
  StepName('remove_existing_cluster_issuer'): RegisteredStep(
    name: StepName('remove_existing_cluster_issuer'),
    source: 'lib/src/steps/remove_existing_cluster_issuer.dart:10',
    create: RemoveExistingClusterIssuer.fromArguments,
    arguments: RemoveExistingClusterIssuer.arguments,
  ),
  // Rendered before it is applied, and both are given the same file under the same name.
  StepName('write_cluster_issuer_manifest'): RegisteredStep(
    name: StepName('write_cluster_issuer_manifest'),
    source: 'lib/src/steps/write_cluster_issuer_manifest.dart:21',
    create: WriteClusterIssuerManifest.fromArguments,
    arguments: WriteClusterIssuerManifest.arguments,
    answers: WriteClusterIssuerManifest.answers,
  ),
  StepName('apply_cluster_issuer'): RegisteredStep(
    name: StepName('apply_cluster_issuer'),
    source: 'lib/src/steps/apply_cluster_issuer.dart:24',
    create: ApplyClusterIssuer.fromArguments,
    arguments: ApplyClusterIssuer.arguments,
  ),
  StepName('restart_cert_manager_and_reapply_cluster_issuer'): RegisteredStep(
    name: StepName('restart_cert_manager_and_reapply_cluster_issuer'),
    source: 'lib/src/steps/restart_cert_manager_and_reapply_cluster_issuer.dart:16',
    create: RestartCertManagerAndReapplyClusterIssuer.fromArguments,
    arguments: RestartCertManagerAndReapplyClusterIssuer.arguments,
  ),
  StepName('kubernetes_namespace'): RegisteredStep(
    name: StepName('kubernetes_namespace'),
    source: 'lib/src/steps/kubernetes_namespace.dart:16',
    create: KubernetesNamespace.fromArguments,
    arguments: KubernetesNamespace.arguments,
  ),
  StepName('kubernetes_configmap_from_directory'): RegisteredStep(
    name: StepName('kubernetes_configmap_from_directory'),
    source: 'lib/src/steps/kubernetes_configmap_from_directory.dart:27',
    create: KubernetesConfigmapFromDirectory.fromArguments,
    arguments: KubernetesConfigmapFromDirectory.arguments,
  ),
  StepName('kubernetes_object_reversible'): RegisteredStep(
    name: StepName('kubernetes_object_reversible'),
    source: 'lib/src/steps/kubernetes_object_reversible.dart:29',
    create: KubernetesObjectReversible.fromArguments,
    arguments: KubernetesObjectReversible.arguments,
  ),
  // The guarded removal: it deletes what a manifest names ONLY where every live object carries the
  // ownership label the row states, so a name collision is refused rather than deleted.
  StepName('remove_kubernetes_object'): RegisteredStep(
    name: StepName('remove_kubernetes_object'),
    source: 'lib/src/steps/remove_kubernetes_object.dart:23',
    create: RemoveKubernetesObject.fromArguments,
    arguments: RemoveKubernetesObject.arguments,
  ),
  // The credentials another machine's manager drives this cluster with, harvested into one file
  // the row names. Which answer holds the address the other side dials is the row's to say.
  StepName('export_cluster_credentials'): RegisteredStep(
    name: StepName('export_cluster_credentials'),
    source: 'lib/src/steps/export_cluster_credentials.dart:27',
    create: ExportClusterCredentials.fromArguments,
    arguments: ExportClusterCredentials.arguments,
  ),
  StepName('kubernetes_object_irreversible'): RegisteredStep(
    name: StepName('kubernetes_object_irreversible'),
    source: 'lib/src/steps/kubernetes_object_irreversible.dart:30',
    create: KubernetesObjectIrreversible.fromArguments,
    arguments: KubernetesObjectIrreversible.arguments,
  ),
  StepName('oidc_admins_binding'): RegisteredStep(
    name: StepName('oidc_admins_binding'),
    source: 'lib/src/steps/oidc_admins_binding.dart:23',
    create: OidcAdminsBinding.fromArguments,
    arguments: OidcAdminsBinding.arguments,
  ),
};

/// This plugin's registry: its steps, and no predicate.
///
/// A predicate is a named condition about one installation — which part is switched on, where a
/// build plane runs. Those are the product's to declare; a tool plugin has none.
const Registry kubernetesRegistry = Registry(
  steps: kubernetesSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
