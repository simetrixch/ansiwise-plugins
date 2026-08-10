import 'package:ansiwise_api/ansiwise_api.dart';
import 'steps/host/activate_public_src_routing.dart';
import 'steps/host/add_shell_alias.dart';
import 'steps/host/add_user_to_group.dart';
import 'steps/host/apply_netplan.dart';
import 'steps/host/assert_cli_tool_versions.dart';
import 'steps/host/assert_netplan_merged.dart';
import 'steps/host/check_storage_mount.dart';
import 'steps/host/clean_package_cache.dart';
import 'steps/host/create_storage_directory.dart';
import 'steps/host/detect_host_iptables_backend.dart';
import 'steps/host/detect_host_upstream_resolvers.dart';
import 'steps/host/detect_public_nic.dart';
import 'steps/host/disable_password_login.dart';
import 'steps/host/ensure_tool_prerequisites.dart';
import 'steps/host/export_kubeconfig.dart';
import 'steps/host/install_authorized_key.dart';
import 'steps/host/install_packages.dart';
import 'steps/host/install_pinned_tool.dart';
import 'steps/host/install_snap.dart';
import 'steps/host/install_tailscale_client.dart';
import 'steps/host/link_microk8s_storage_path.dart';
import 'steps/host/remove_snap.dart';
import 'steps/host/remove_unused_packages.dart';
import 'steps/host/require_commands.dart';
import 'steps/host/require_free_disk.dart';
import 'steps/host/require_key_login_possible.dart';
import 'steps/host/require_machine_size.dart';
import 'steps/host/require_pinned_ubuntu.dart';
import 'steps/host/set_process_flag.dart';
import 'steps/host/write_connmark_nft_table.dart';
import 'steps/host/write_netplan_public_src_routing.dart';
import 'steps/host/write_public_src_routing_script.dart';
import 'steps/host/write_public_src_routing_unit.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection. That is not a workaround
/// — it is what lets a check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> hostSteps = <StepName, RegisteredStep>{
  // Gates that refuse a machine before anything is written to it.
  StepName('require_pinned_ubuntu'): RegisteredStep(
    name: StepName('require_pinned_ubuntu'),
    source: 'lib/src/steps/host/require_pinned_ubuntu.dart:11',
    create: RequirePinnedUbuntu.fromArguments,
    arguments: RequirePinnedUbuntu.arguments,
  ),
  StepName('require_machine_size'): RegisteredStep(
    name: StepName('require_machine_size'),
    source: 'lib/src/steps/host/require_machine_size.dart:12',
    create: RequireMachineSize.fromArguments,
    arguments: RequireMachineSize.arguments,
  ),
  StepName('require_free_disk'): RegisteredStep(
    name: StepName('require_free_disk'),
    source: 'lib/src/steps/host/require_free_disk.dart:8',
    create: RequireFreeDisk.fromArguments,
    arguments: RequireFreeDisk.arguments,
  ),
  StepName('require_commands'): RegisteredStep(
    name: StepName('require_commands'),
    source: 'lib/src/steps/host/require_commands.dart:16',
    create: RequireCommands.fromArguments,
    arguments: RequireCommands.arguments,
  ),
  // The package manager.
  StepName('install_packages'): RegisteredStep(
    name: StepName('install_packages'),
    source: 'lib/src/steps/host/install_packages.dart:14',
    create: InstallPackages.fromArguments,
    arguments: InstallPackages.arguments,
  ),
  StepName('remove_unused_packages'): RegisteredStep(
    name: StepName('remove_unused_packages'),
    source: 'lib/src/steps/host/remove_unused_packages.dart:8',
    create: RemoveUnusedPackages.fromArguments,
    arguments: RemoveUnusedPackages.arguments,
  ),
  StepName('clean_package_cache'): RegisteredStep(
    name: StepName('clean_package_cache'),
    source: 'lib/src/steps/host/clean_package_cache.dart:10',
    create: CleanPackageCache.fromArguments,
    arguments: CleanPackageCache.arguments,
  ),
  // The key login, and the door that closes only after it is proven.
  StepName('install_authorized_key'): RegisteredStep(
    name: StepName('install_authorized_key'),
    source: 'lib/src/steps/host/install_authorized_key.dart:12',
    create: InstallAuthorizedKey.fromArguments,
    arguments: InstallAuthorizedKey.arguments,
    answers: InstallAuthorizedKey.answers,
  ),
  StepName('require_key_login_possible'): RegisteredStep(
    name: StepName('require_key_login_possible'),
    source: 'lib/src/steps/host/require_key_login_possible.dart:20',
    create: RequireKeyLoginPossible.fromArguments,
    arguments: RequireKeyLoginPossible.arguments,
    answers: RequireKeyLoginPossible.answers,
  ),
  StepName('disable_password_login'): RegisteredStep(
    name: StepName('disable_password_login'),
    source: 'lib/src/steps/host/disable_password_login.dart:15',
    create: DisablePasswordLogin.fromArguments,
    arguments: DisablePasswordLogin.arguments,
  ),
  // Snaps.
  StepName('remove_snap'): RegisteredStep(
    name: StepName('remove_snap'),
    source: 'lib/src/steps/host/remove_snap.dart:22',
    create: RemoveSnap.fromArguments,
    arguments: RemoveSnap.arguments,
  ),
  StepName('install_snap'): RegisteredStep(
    name: StepName('install_snap'),
    source: 'lib/src/steps/host/install_snap.dart:35',
    create: InstallSnap.fromArguments,
    arguments: InstallSnap.arguments,
  ),
  StepName('set_process_flag'): RegisteredStep(
    name: StepName('set_process_flag'),
    source: 'lib/src/steps/host/set_process_flag.dart:31',
    create: SetProcessFlag.fromArguments,
    arguments: SetProcessFlag.arguments,
  ),
  // The operator's account.
  StepName('add_user_to_group'): RegisteredStep(
    name: StepName('add_user_to_group'),
    source: 'lib/src/steps/host/add_user_to_group.dart:12',
    create: AddUserToGroup.fromArguments,
    arguments: AddUserToGroup.arguments,
    answers: AddUserToGroup.answers,
  ),
  StepName('add_shell_alias'): RegisteredStep(
    name: StepName('add_shell_alias'),
    source: 'lib/src/steps/host/add_shell_alias.dart:11',
    create: AddShellAlias.fromArguments,
    arguments: AddShellAlias.arguments,
    answers: AddShellAlias.answers,
  ),
  StepName('export_kubeconfig'): RegisteredStep(
    name: StepName('export_kubeconfig'),
    source: 'lib/src/steps/host/export_kubeconfig.dart:21',
    create: ExportKubeconfig.fromArguments,
    arguments: ExportKubeconfig.arguments,
    answers: ExportKubeconfig.answers,
  ),
  // Storage.
  StepName('check_storage_mount'): RegisteredStep(
    name: StepName('check_storage_mount'),
    source: 'lib/src/steps/host/check_storage_mount.dart:12',
    create: CheckStorageMount.fromArguments,
    arguments: CheckStorageMount.arguments,
    answers: CheckStorageMount.answers,
  ),
  StepName('create_storage_directory'): RegisteredStep(
    name: StepName('create_storage_directory'),
    source: 'lib/src/steps/host/create_storage_directory.dart:9',
    create: CreateStorageDirectory.fromArguments,
    arguments: CreateStorageDirectory.arguments,
    answers: CreateStorageDirectory.answers,
  ),
  StepName('link_microk8s_storage_path'): RegisteredStep(
    name: StepName('link_microk8s_storage_path'),
    source: 'lib/src/steps/host/link_microk8s_storage_path.dart:13',
    create: LinkMicrok8sStoragePath.fromArguments,
    arguments: LinkMicrok8sStoragePath.arguments,
    answers: LinkMicrok8sStoragePath.answers,
  ),
  // Tools fetched onto the machine.
  StepName('ensure_tool_prerequisites'): RegisteredStep(
    name: StepName('ensure_tool_prerequisites'),
    source: 'lib/src/steps/host/ensure_tool_prerequisites.dart:14',
    create: EnsureToolPrerequisites.fromArguments,
    arguments: EnsureToolPrerequisites.arguments,
  ),
  StepName('install_pinned_tool'): RegisteredStep(
    name: StepName('install_pinned_tool'),
    source: 'lib/src/steps/host/install_pinned_tool.dart:39',
    create: InstallPinnedTool.fromArguments,
    arguments: InstallPinnedTool.arguments,
  ),
  StepName('install_tailscale_client'): RegisteredStep(
    name: StepName('install_tailscale_client'),
    source: 'lib/src/steps/host/install_tailscale_client.dart:18',
    create: InstallTailscaleClient.fromArguments,
    arguments: InstallTailscaleClient.arguments,
  ),
  StepName('assert_cli_tool_versions'): RegisteredStep(
    name: StepName('assert_cli_tool_versions'),
    source: 'lib/src/steps/host/assert_cli_tool_versions.dart:28',
    create: AssertCliToolVersions.fromArguments,
    arguments: AssertCliToolVersions.arguments,
  ),
  // Steering replies on a machine whose public address arrives on one interface while another
  // owns the default route. The entries stand in the order a program runs them.
  StepName('detect_public_nic'): RegisteredStep(
    name: StepName('detect_public_nic'),
    source: 'lib/src/steps/host/detect_public_nic.dart:19',
    create: DetectPublicNic.fromArguments,
    arguments: DetectPublicNic.arguments,
  ),
  StepName('write_netplan_public_src_routing'): RegisteredStep(
    name: StepName('write_netplan_public_src_routing'),
    source: 'lib/src/steps/host/write_netplan_public_src_routing.dart:25',
    create: WriteNetplanPublicSrcRouting.fromArguments,
    arguments: WriteNetplanPublicSrcRouting.arguments,
  ),
  StepName('assert_netplan_merged'): RegisteredStep(
    name: StepName('assert_netplan_merged'),
    source: 'lib/src/steps/host/assert_netplan_merged.dart:15',
    create: AssertNetplanMerged.fromArguments,
    arguments: AssertNetplanMerged.arguments,
  ),
  StepName('apply_netplan'): RegisteredStep(
    name: StepName('apply_netplan'),
    source: 'lib/src/steps/host/apply_netplan.dart:12',
    create: ApplyNetplan.fromArguments,
    arguments: ApplyNetplan.arguments,
  ),
  StepName('write_connmark_nft_table'): RegisteredStep(
    name: StepName('write_connmark_nft_table'),
    source: 'lib/src/steps/host/write_connmark_nft_table.dart:20',
    create: WriteConnmarkNftTable.fromArguments,
    arguments: WriteConnmarkNftTable.arguments,
  ),
  StepName('write_public_src_routing_script'): RegisteredStep(
    name: StepName('write_public_src_routing_script'),
    source: 'lib/src/steps/host/write_public_src_routing_script.dart:15',
    create: WritePublicSrcRoutingScript.fromArguments,
    arguments: WritePublicSrcRoutingScript.arguments,
  ),
  StepName('write_public_src_routing_unit'): RegisteredStep(
    name: StepName('write_public_src_routing_unit'),
    source: 'lib/src/steps/host/write_public_src_routing_unit.dart:14',
    create: WritePublicSrcRoutingUnit.fromArguments,
    arguments: WritePublicSrcRoutingUnit.arguments,
  ),
  StepName('activate_public_src_routing'): RegisteredStep(
    name: StepName('activate_public_src_routing'),
    source: 'lib/src/steps/host/activate_public_src_routing.dart:10',
    create: ActivatePublicSrcRouting.fromArguments,
    arguments: ActivatePublicSrcRouting.arguments,
  ),
  // Measurements the network conversion of a cluster asks for.
  StepName('detect_host_upstream_resolvers'): RegisteredStep(
    name: StepName('detect_host_upstream_resolvers'),
    source: 'lib/src/steps/host/detect_host_upstream_resolvers.dart:21',
    create: DetectHostUpstreamResolvers.fromArguments,
    arguments: DetectHostUpstreamResolvers.arguments,
  ),
  StepName('detect_host_iptables_backend'): RegisteredStep(
    name: StepName('detect_host_iptables_backend'),
    source: 'lib/src/steps/host/detect_host_iptables_backend.dart:13',
    create: DetectHostIptablesBackend.fromArguments,
    arguments: DetectHostIptablesBackend.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about an installation, and an installation is what
/// this package deliberately knows nothing about.
const Registry hostRegistry = Registry(
  steps: hostSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
