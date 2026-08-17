/// Tool-generic steps that prepare and drive a Linux host.
///
/// This package knows tools — apt, dpkg, snap, sshd, systemd, netplan, nft, ip, curl, mount, the
/// container runtime — and never an application of them. Every name a product decides — a file
/// path, an nft table, a service unit, the registry it mirrors — is a required argument, and the
/// value stands in that product's program row.
library;

export 'src/conditions/key_is_true.dart';
export 'src/conditions/keys_compare.dart';
export 'src/registry.dart';
export 'src/steps/host/activate_public_src_routing.dart';
export 'src/steps/host/add_shell_alias.dart';
export 'src/steps/host/add_user_to_group.dart';
export 'src/steps/host/addon_status.dart';
export 'src/steps/host/apply_netplan.dart';
export 'src/steps/host/assert_cli_tool_versions.dart';
export 'src/steps/host/assert_netplan_merged.dart';
export 'src/steps/host/check_storage_mount.dart';
export 'src/steps/host/clean_package_cache.dart';
export 'src/steps/host/create_file_from_template.dart';
export 'src/steps/host/create_storage_directory.dart';
export 'src/steps/host/detect_host_iptables_backend.dart';
export 'src/steps/host/detect_host_upstream_resolvers.dart';
export 'src/steps/host/detect_public_nic.dart';
export 'src/steps/host/disable_addons.dart';
export 'src/steps/host/disable_password_login.dart';
export 'src/steps/host/enable_addons.dart';
export 'src/steps/host/ensure_tool_prerequisites.dart';
export 'src/steps/host/export_kubeconfig.dart';
export 'src/steps/host/install_authorized_key.dart';
export 'src/steps/host/fill_key_value_file.dart';
export 'src/steps/host/key_value_file.dart';
export 'src/steps/host/install_packages.dart';
export 'src/steps/host/install_pinned_tool.dart';
export 'src/steps/host/install_snap.dart';
export 'src/steps/host/install_tailscale_client.dart';
export 'src/steps/host/link_storage_path.dart';
export 'src/steps/host/on_the_path.dart';
export 'src/steps/host/preflight_registry_pull_credential.dart';
export 'src/steps/host/registry_mirror.dart';
export 'src/steps/host/remove_snap.dart';
export 'src/steps/host/remove_unused_packages.dart';
export 'src/steps/host/require_commands.dart';
export 'src/steps/host/require_free_disk.dart';
export 'src/steps/host/require_key_login_possible.dart';
export 'src/steps/host/require_machine_size.dart';
export 'src/steps/host/require_pinned_ubuntu.dart';
export 'src/steps/host/set_process_flag.dart';
export 'src/steps/host/stamp_calico_pool_cidr_in_cni_manifest.dart';
export 'src/steps/host/wait_for_addons_enabled.dart';
export 'src/steps/host/write_connmark_nft_table.dart';
export 'src/steps/host/write_containerd_registry_mirror.dart';
export 'src/steps/host/write_file_from_template.dart';
export 'src/steps/host/write_netplan_public_src_routing.dart';
export 'src/steps/host/write_public_src_routing_script.dart';
export 'src/steps/host/write_public_src_routing_unit.dart';
export 'src/plugin.dart';
