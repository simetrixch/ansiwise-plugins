import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/cluster/activate_public_src_routing.dart';
import '../steps/cluster/add_shell_alias.dart';
import '../steps/cluster/add_user_to_group.dart';
import '../steps/cluster/align_calico_backend.dart';
import '../steps/cluster/apply_cluster_issuer.dart';
import '../steps/cluster/apply_netplan.dart';
import '../steps/cluster/assert_cli_tool_versions.dart';
import '../steps/cluster/assert_netplan_merged.dart';
import '../steps/cluster/check_storage_mount.dart';
import '../steps/cluster/configure_kube_apiserver_oidc.dart';
import '../steps/cluster/configure_kube_proxy_nftables.dart';
import '../steps/cluster/configure_slave_apiserver_oidc_trust.dart';
import '../steps/cluster/create_storage_directory.dart';
import '../steps/cluster/delete_default_ipv4_ippool.dart';
import '../steps/cluster/delete_existing_cluster_issuer.dart';
import '../steps/cluster/detect_host_iptables_backend.dart';
import '../steps/cluster/detect_host_upstream_resolvers.dart';
import '../steps/cluster/detect_public_nic.dart';
import '../steps/cluster/disable_addons.dart';
import '../steps/cluster/enable_addons.dart';
import '../steps/cluster/enable_disabled_microk8s_snap.dart';
import '../steps/cluster/ensure_tool_prerequisites.dart';
import '../steps/cluster/export_kubeconfig.dart';
import '../steps/cluster/force_roll_traefik_daemonset.dart';
import '../steps/cluster/guard_populated_cluster_pod_cidr_migration.dart';
import '../steps/cluster/install_argocd_cli.dart';
import '../steps/cluster/install_jq.dart';
import '../steps/cluster/install_microk8s_snap.dart';
import '../steps/cluster/install_tailscale_client.dart';
import '../steps/cluster/install_vault_cli.dart';
import '../steps/cluster/install_yq_cli.dart';
import '../steps/cluster/link_microk8s_storage_path.dart';
import '../steps/cluster/patch_coredns_corefile.dart';
import '../steps/cluster/patch_traefik_cross_namespace.dart';
import '../steps/cluster/patch_traefik_tcp_entrypoint.dart';
import '../steps/cluster/preflight_docker_mirror_credential.dart';
import '../steps/cluster/reapply_calico_manifest.dart';
import '../steps/cluster/recycle_kube_system_pod_ips.dart';
import '../steps/cluster/refresh_microk8s_channel.dart';
import '../steps/cluster/remove_microk8s_snap_forced.dart';
import '../steps/cluster/require_pod_cidr_free_of_reserved_ranges.dart';
import '../steps/cluster/restart_cert_manager_and_reapply_cluster_issuer.dart';
import '../steps/cluster/restart_microk8s_snap_for_pod_cidr.dart';
import '../steps/cluster/set_default_storage_class.dart';
import '../steps/cluster/stamp_calico_pool_cidr_in_cni_manifest.dart';
import '../steps/cluster/stamp_kube_proxy_cluster_cidr.dart';
import '../steps/cluster/verify_ippool_converged_with_self_heal.dart';
import '../steps/cluster/wait_cluster_issuer_ready.dart';
import '../steps/cluster/wait_for_addons_enabled.dart';
import '../steps/cluster/wait_for_cert_manager_ready.dart';
import '../steps/cluster/wait_for_microk8s_ready.dart';
import '../steps/cluster/write_cluster_issuer_manifest.dart';
import '../steps/cluster/write_connmark_nft_table.dart';
import '../steps/cluster/write_containerd_docker_mirror.dart';
import '../steps/cluster/write_netplan_public_src_routing.dart';
import '../steps/cluster/write_public_src_routing_script.dart';
import '../steps/cluster/write_public_src_routing_unit.dart';

/// Every step that turns a prepared machine into a cluster the platform can be deployed onto.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
///
/// The entries are written in the order the program runs them, and that order is itself a
/// constraint: the packet-filtering backend before any addon paints a rule, the pod network before
/// any pod is given an address, the image mirror before any image is pulled, and the addons before
/// anything that patches what an addon installed.
const Map<StepName, RegisteredStep> clusterSteps = <StepName, RegisteredStep>{
  StepName('remove_microk8s_snap_forced'): RegisteredStep(
    name: StepName('remove_microk8s_snap_forced'),
    source: 'lib/src/steps/cluster/remove_microk8s_snap_forced.dart:16',
    create: RemoveMicrok8sSnapForced.fromArguments,
    arguments: RemoveMicrok8sSnapForced.arguments,
  ),
  StepName('enable_disabled_microk8s_snap'): RegisteredStep(
    name: StepName('enable_disabled_microk8s_snap'),
    source: 'lib/src/steps/cluster/enable_disabled_microk8s_snap.dart:16',
    create: EnableDisabledMicrok8sSnap.fromArguments,
    arguments: EnableDisabledMicrok8sSnap.arguments,
  ),
  StepName('refresh_microk8s_channel'): RegisteredStep(
    name: StepName('refresh_microk8s_channel'),
    source: 'lib/src/steps/cluster/refresh_microk8s_channel.dart:15',
    create: RefreshMicrok8sChannel.fromArguments,
    arguments: RefreshMicrok8sChannel.arguments,
  ),
  StepName('install_microk8s_snap'): RegisteredStep(
    name: StepName('install_microk8s_snap'),
    source: 'lib/src/steps/cluster/install_microk8s_snap.dart:16',
    create: InstallMicrok8sSnap.fromArguments,
    arguments: InstallMicrok8sSnap.arguments,
  ),
  StepName('wait_for_microk8s_ready'): RegisteredStep(
    name: StepName('wait_for_microk8s_ready'),
    source: 'lib/src/steps/cluster/wait_for_microk8s_ready.dart:13',
    create: WaitForMicrok8sReady.fromArguments,
    arguments: WaitForMicrok8sReady.arguments,
  ),
  StepName('configure_kube_proxy_nftables'): RegisteredStep(
    name: StepName('configure_kube_proxy_nftables'),
    source: 'lib/src/steps/cluster/configure_kube_proxy_nftables.dart:15',
    create: ConfigureKubeProxyNftables.fromArguments,
    arguments: ConfigureKubeProxyNftables.arguments,
  ),
  StepName('require_pod_cidr_free_of_reserved_ranges'): RegisteredStep(
    name: StepName('require_pod_cidr_free_of_reserved_ranges'),
    source: 'lib/src/steps/cluster/require_pod_cidr_free_of_reserved_ranges.dart:20',
    create: RequirePodCidrFreeOfReservedRanges.fromArguments,
    arguments: RequirePodCidrFreeOfReservedRanges.arguments,
    answers: RequirePodCidrFreeOfReservedRanges.answers,
  ),
  StepName('guard_populated_cluster_pod_cidr_migration'): RegisteredStep(
    name: StepName('guard_populated_cluster_pod_cidr_migration'),
    source: 'lib/src/steps/cluster/guard_populated_cluster_pod_cidr_migration.dart:24',
    create: GuardPopulatedClusterPodCidrMigration.fromArguments,
    arguments: GuardPopulatedClusterPodCidrMigration.arguments,
  ),
  StepName('stamp_calico_pool_cidr_in_cni_manifest'): RegisteredStep(
    name: StepName('stamp_calico_pool_cidr_in_cni_manifest'),
    source: 'lib/src/steps/cluster/stamp_calico_pool_cidr_in_cni_manifest.dart:20',
    create: StampCalicoPoolCidrInCniManifest.fromArguments,
    arguments: StampCalicoPoolCidrInCniManifest.arguments,
  ),
  StepName('stamp_kube_proxy_cluster_cidr'): RegisteredStep(
    name: StepName('stamp_kube_proxy_cluster_cidr'),
    source: 'lib/src/steps/cluster/stamp_kube_proxy_cluster_cidr.dart:18',
    create: StampKubeProxyClusterCidr.fromArguments,
    arguments: StampKubeProxyClusterCidr.arguments,
  ),
  StepName('delete_default_ipv4_ippool'): RegisteredStep(
    name: StepName('delete_default_ipv4_ippool'),
    source: 'lib/src/steps/cluster/delete_default_ipv4_ippool.dart:16',
    create: DeleteDefaultIpv4Ippool.fromArguments,
    arguments: DeleteDefaultIpv4Ippool.arguments,
  ),
  StepName('reapply_calico_manifest'): RegisteredStep(
    name: StepName('reapply_calico_manifest'),
    source: 'lib/src/steps/cluster/reapply_calico_manifest.dart:14',
    create: ReapplyCalicoManifest.fromArguments,
    arguments: ReapplyCalicoManifest.arguments,
  ),
  StepName('restart_microk8s_snap_for_pod_cidr'): RegisteredStep(
    name: StepName('restart_microk8s_snap_for_pod_cidr'),
    source: 'lib/src/steps/cluster/restart_microk8s_snap_for_pod_cidr.dart:19',
    create: RestartMicrok8sSnapForPodCidr.fromArguments,
    arguments: RestartMicrok8sSnapForPodCidr.arguments,
  ),
  StepName('verify_ippool_converged_with_self_heal'): RegisteredStep(
    name: StepName('verify_ippool_converged_with_self_heal'),
    source: 'lib/src/steps/cluster/verify_ippool_converged_with_self_heal.dart:19',
    create: VerifyIppoolConvergedWithSelfHeal.fromArguments,
    arguments: VerifyIppoolConvergedWithSelfHeal.arguments,
  ),
  StepName('recycle_kube_system_pod_ips'): RegisteredStep(
    name: StepName('recycle_kube_system_pod_ips'),
    source: 'lib/src/steps/cluster/recycle_kube_system_pod_ips.dart:18',
    create: RecycleKubeSystemPodIps.fromArguments,
    arguments: RecycleKubeSystemPodIps.arguments,
  ),
  StepName('preflight_docker_mirror_credential'): RegisteredStep(
    name: StepName('preflight_docker_mirror_credential'),
    source: 'lib/src/steps/cluster/preflight_docker_mirror_credential.dart:29',
    create: PreflightDockerMirrorCredential.fromArguments,
    arguments: PreflightDockerMirrorCredential.arguments,
    answers: PreflightDockerMirrorCredential.answers,
  ),
  StepName('write_containerd_docker_mirror'): RegisteredStep(
    name: StepName('write_containerd_docker_mirror'),
    source: 'lib/src/steps/cluster/write_containerd_docker_mirror.dart:24',
    create: WriteContainerdDockerMirror.fromArguments,
    arguments: WriteContainerdDockerMirror.arguments,
    answers: WriteContainerdDockerMirror.answers,
  ),
  StepName('add_user_to_group'): RegisteredStep(
    name: StepName('add_user_to_group'),
    source: 'lib/src/steps/cluster/add_user_to_group.dart:13',
    create: AddUserToGroup.fromArguments,
    arguments: AddUserToGroup.arguments,
    answers: AddUserToGroup.answers,
  ),
  StepName('enable_addons'): RegisteredStep(
    name: StepName('enable_addons'),
    source: 'lib/src/steps/cluster/enable_addons.dart:17',
    create: EnableAddons.fromArguments,
    arguments: EnableAddons.arguments,
  ),
  StepName('wait_for_addons_enabled'): RegisteredStep(
    name: StepName('wait_for_addons_enabled'),
    source: 'lib/src/steps/cluster/wait_for_addons_enabled.dart:12',
    create: WaitForAddonsEnabled.fromArguments,
    arguments: WaitForAddonsEnabled.arguments,
  ),
  StepName('detect_host_upstream_resolvers'): RegisteredStep(
    name: StepName('detect_host_upstream_resolvers'),
    source: 'lib/src/steps/cluster/detect_host_upstream_resolvers.dart:21',
    create: DetectHostUpstreamResolvers.fromArguments,
    arguments: DetectHostUpstreamResolvers.arguments,
  ),
  StepName('patch_coredns_corefile'): RegisteredStep(
    name: StepName('patch_coredns_corefile'),
    source: 'lib/src/steps/cluster/patch_coredns_corefile.dart:26',
    create: PatchCorednsCorefile.fromArguments,
    arguments: PatchCorednsCorefile.arguments,
  ),
  StepName('detect_host_iptables_backend'): RegisteredStep(
    name: StepName('detect_host_iptables_backend'),
    source: 'lib/src/steps/cluster/detect_host_iptables_backend.dart:13',
    create: DetectHostIptablesBackend.fromArguments,
    arguments: DetectHostIptablesBackend.arguments,
  ),
  StepName('align_calico_backend'): RegisteredStep(
    name: StepName('align_calico_backend'),
    source: 'lib/src/steps/cluster/align_calico_backend.dart:23',
    create: AlignCalicoBackend.fromArguments,
    arguments: AlignCalicoBackend.arguments,
  ),
  StepName('patch_traefik_cross_namespace'): RegisteredStep(
    name: StepName('patch_traefik_cross_namespace'),
    source: 'lib/src/steps/cluster/patch_traefik_cross_namespace.dart:19',
    create: PatchTraefikCrossNamespace.fromArguments,
    arguments: PatchTraefikCrossNamespace.arguments,
  ),
  StepName('patch_traefik_tcp_entrypoint'): RegisteredStep(
    name: StepName('patch_traefik_tcp_entrypoint'),
    source: 'lib/src/steps/cluster/patch_traefik_tcp_entrypoint.dart:19',
    create: PatchTraefikTcpEntrypoint.fromArguments,
    arguments: PatchTraefikTcpEntrypoint.arguments,
  ),
  StepName('force_roll_traefik_daemonset'): RegisteredStep(
    name: StepName('force_roll_traefik_daemonset'),
    source: 'lib/src/steps/cluster/force_roll_traefik_daemonset.dart:21',
    create: ForceRollTraefikDaemonset.fromArguments,
    arguments: ForceRollTraefikDaemonset.arguments,
  ),
  StepName('disable_addons'): RegisteredStep(
    name: StepName('disable_addons'),
    source: 'lib/src/steps/cluster/disable_addons.dart:17',
    create: DisableAddons.fromArguments,
    arguments: DisableAddons.arguments,
  ),
  StepName('configure_kube_apiserver_oidc'): RegisteredStep(
    name: StepName('configure_kube_apiserver_oidc'),
    source: 'lib/src/steps/cluster/configure_kube_apiserver_oidc.dart:17',
    create: ConfigureKubeApiserverOidc.fromArguments,
    arguments: ConfigureKubeApiserverOidc.arguments,
    answers: ConfigureKubeApiserverOidc.answers,
  ),
  StepName('configure_slave_apiserver_oidc_trust'): RegisteredStep(
    name: StepName('configure_slave_apiserver_oidc_trust'),
    source: 'lib/src/steps/cluster/configure_slave_apiserver_oidc_trust.dart:19',
    create: ConfigureSlaveApiserverOidcTrust.fromArguments,
    arguments: ConfigureSlaveApiserverOidcTrust.arguments,
    answers: ConfigureSlaveApiserverOidcTrust.answers,
  ),
  StepName('detect_public_nic'): RegisteredStep(
    name: StepName('detect_public_nic'),
    source: 'lib/src/steps/cluster/detect_public_nic.dart:19',
    create: DetectPublicNic.fromArguments,
    arguments: DetectPublicNic.arguments,
  ),
  StepName('write_netplan_public_src_routing'): RegisteredStep(
    name: StepName('write_netplan_public_src_routing'),
    source: 'lib/src/steps/cluster/write_netplan_public_src_routing.dart:22',
    create: WriteNetplanPublicSrcRouting.fromArguments,
    arguments: WriteNetplanPublicSrcRouting.arguments,
  ),
  StepName('assert_netplan_merged'): RegisteredStep(
    name: StepName('assert_netplan_merged'),
    source: 'lib/src/steps/cluster/assert_netplan_merged.dart:15',
    create: AssertNetplanMerged.fromArguments,
    arguments: AssertNetplanMerged.arguments,
  ),
  StepName('apply_netplan'): RegisteredStep(
    name: StepName('apply_netplan'),
    source: 'lib/src/steps/cluster/apply_netplan.dart:13',
    create: ApplyNetplan.fromArguments,
    arguments: ApplyNetplan.arguments,
  ),
  StepName('write_connmark_nft_table'): RegisteredStep(
    name: StepName('write_connmark_nft_table'),
    source: 'lib/src/steps/cluster/write_connmark_nft_table.dart:20',
    create: WriteConnmarkNftTable.fromArguments,
    arguments: WriteConnmarkNftTable.arguments,
  ),
  StepName('write_public_src_routing_script'): RegisteredStep(
    name: StepName('write_public_src_routing_script'),
    source: 'lib/src/steps/cluster/write_public_src_routing_script.dart:17',
    create: WritePublicSrcRoutingScript.fromArguments,
    arguments: WritePublicSrcRoutingScript.arguments,
  ),
  StepName('write_public_src_routing_unit'): RegisteredStep(
    name: StepName('write_public_src_routing_unit'),
    source: 'lib/src/steps/cluster/write_public_src_routing_unit.dart:17',
    create: WritePublicSrcRoutingUnit.fromArguments,
    arguments: WritePublicSrcRoutingUnit.arguments,
  ),
  StepName('activate_public_src_routing'): RegisteredStep(
    name: StepName('activate_public_src_routing'),
    source: 'lib/src/steps/cluster/activate_public_src_routing.dart:13',
    create: ActivatePublicSrcRouting.fromArguments,
    arguments: ActivatePublicSrcRouting.arguments,
  ),
  StepName('check_storage_mount'): RegisteredStep(
    name: StepName('check_storage_mount'),
    source: 'lib/src/steps/cluster/check_storage_mount.dart:12',
    create: CheckStorageMount.fromArguments,
    arguments: CheckStorageMount.arguments,
    answers: CheckStorageMount.answers,
  ),
  StepName('create_storage_directory'): RegisteredStep(
    name: StepName('create_storage_directory'),
    source: 'lib/src/steps/cluster/create_storage_directory.dart:9',
    create: CreateStorageDirectory.fromArguments,
    arguments: CreateStorageDirectory.arguments,
    answers: CreateStorageDirectory.answers,
  ),
  StepName('link_microk8s_storage_path'): RegisteredStep(
    name: StepName('link_microk8s_storage_path'),
    source: 'lib/src/steps/cluster/link_microk8s_storage_path.dart:13',
    create: LinkMicrok8sStoragePath.fromArguments,
    arguments: LinkMicrok8sStoragePath.arguments,
    answers: LinkMicrok8sStoragePath.answers,
  ),
  StepName('set_default_storage_class'): RegisteredStep(
    name: StepName('set_default_storage_class'),
    source: 'lib/src/steps/cluster/set_default_storage_class.dart:18',
    create: SetDefaultStorageClass.fromArguments,
    arguments: SetDefaultStorageClass.arguments,
  ),
  StepName('wait_for_cert_manager_ready'): RegisteredStep(
    name: StepName('wait_for_cert_manager_ready'),
    source: 'lib/src/steps/cluster/wait_for_cert_manager_ready.dart:11',
    create: WaitForCertManagerReady.fromArguments,
    arguments: WaitForCertManagerReady.arguments,
  ),
  StepName('delete_existing_cluster_issuer'): RegisteredStep(
    name: StepName('delete_existing_cluster_issuer'),
    source: 'lib/src/steps/cluster/delete_existing_cluster_issuer.dart:8',
    create: DeleteExistingClusterIssuer.fromArguments,
    arguments: DeleteExistingClusterIssuer.arguments,
  ),
  StepName('write_cluster_issuer_manifest'): RegisteredStep(
    name: StepName('write_cluster_issuer_manifest'),
    source: 'lib/src/steps/cluster/write_cluster_issuer_manifest.dart:14',
    create: WriteClusterIssuerManifest.fromArguments,
    arguments: WriteClusterIssuerManifest.arguments,
    answers: WriteClusterIssuerManifest.answers,
  ),
  StepName('apply_cluster_issuer'): RegisteredStep(
    name: StepName('apply_cluster_issuer'),
    source: 'lib/src/steps/cluster/apply_cluster_issuer.dart:9',
    create: ApplyClusterIssuer.fromArguments,
    arguments: ApplyClusterIssuer.arguments,
  ),
  StepName('wait_cluster_issuer_ready'): RegisteredStep(
    name: StepName('wait_cluster_issuer_ready'),
    source: 'lib/src/steps/cluster/wait_cluster_issuer_ready.dart:11',
    create: WaitClusterIssuerReady.fromArguments,
    arguments: WaitClusterIssuerReady.arguments,
  ),
  StepName('restart_cert_manager_and_reapply_cluster_issuer'): RegisteredStep(
    name: StepName('restart_cert_manager_and_reapply_cluster_issuer'),
    source: 'lib/src/steps/cluster/restart_cert_manager_and_reapply_cluster_issuer.dart:19',
    create: RestartCertManagerAndReapplyClusterIssuer.fromArguments,
    arguments: RestartCertManagerAndReapplyClusterIssuer.arguments,
  ),
  StepName('ensure_tool_prerequisites'): RegisteredStep(
    name: StepName('ensure_tool_prerequisites'),
    source: 'lib/src/steps/cluster/ensure_tool_prerequisites.dart:14',
    create: EnsureToolPrerequisites.fromArguments,
    arguments: EnsureToolPrerequisites.arguments,
  ),
  StepName('install_jq'): RegisteredStep(
    name: StepName('install_jq'),
    source: 'lib/src/steps/cluster/install_jq.dart:14',
    create: InstallJq.fromArguments,
    arguments: InstallJq.arguments,
  ),
  StepName('install_argocd_cli'): RegisteredStep(
    name: StepName('install_argocd_cli'),
    source: 'lib/src/steps/cluster/install_argocd_cli.dart:13',
    create: InstallArgocdCli.fromArguments,
    arguments: InstallArgocdCli.arguments,
  ),
  StepName('install_vault_cli'): RegisteredStep(
    name: StepName('install_vault_cli'),
    source: 'lib/src/steps/cluster/install_vault_cli.dart:9',
    create: InstallVaultCli.fromArguments,
    arguments: InstallVaultCli.arguments,
  ),
  StepName('install_yq_cli'): RegisteredStep(
    name: StepName('install_yq_cli'),
    source: 'lib/src/steps/cluster/install_yq_cli.dart:5',
    create: InstallYqCli.fromArguments,
    arguments: InstallYqCli.arguments,
  ),
  StepName('install_tailscale_client'): RegisteredStep(
    name: StepName('install_tailscale_client'),
    source: 'lib/src/steps/cluster/install_tailscale_client.dart:18',
    create: InstallTailscaleClient.fromArguments,
    arguments: InstallTailscaleClient.arguments,
  ),
  StepName('assert_cli_tool_versions'): RegisteredStep(
    name: StepName('assert_cli_tool_versions'),
    source: 'lib/src/steps/cluster/assert_cli_tool_versions.dart:19',
    create: AssertCliToolVersions.fromArguments,
    arguments: AssertCliToolVersions.arguments,
  ),
  StepName('add_shell_alias'): RegisteredStep(
    name: StepName('add_shell_alias'),
    source: 'lib/src/steps/cluster/add_shell_alias.dart:11',
    create: AddShellAlias.fromArguments,
    arguments: AddShellAlias.arguments,
    answers: AddShellAlias.answers,
  ),
  StepName('export_kubeconfig'): RegisteredStep(
    name: StepName('export_kubeconfig'),
    source: 'lib/src/steps/cluster/export_kubeconfig.dart:15',
    create: ExportKubeconfig.fromArguments,
    arguments: ExportKubeconfig.arguments,
    answers: ExportKubeconfig.answers,
  ),
};
