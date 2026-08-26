/// Steps that drive a Kubernetes cluster through kubectl, for any product built on one.
///
/// This package knows the tool. It carries no default that names a product, an installation's
/// path, or an installation's configuration — where a value belongs to an installation, the
/// argument is required and the value stands in that installation's program row.
library;

export 'src/plugin.dart';
export 'src/registry.dart';
export 'src/steps/align_calico_backend.dart';
export 'src/steps/align_calico_nat_port_range.dart';
export 'src/steps/apply_cluster_issuer.dart';
export 'src/steps/export_cluster_credentials.dart';
export 'src/steps/kubectl.dart';
export 'src/steps/kubernetes_configmap_from_directory.dart';
export 'src/steps/kubernetes_namespace.dart';
export 'src/steps/kubernetes_object_irreversible.dart';
export 'src/steps/kubernetes_object_reversible.dart';
export 'src/steps/oidc_admins_binding.dart';
export 'src/steps/patch_configmap_key.dart';
export 'src/steps/patch_container_arguments_and_ports.dart';
export 'src/steps/reapply_calico_manifest.dart';
export 'src/steps/recycle_kube_system_pod_ips.dart';
export 'src/steps/remove_calico_rules_from_other_backend.dart';
export 'src/steps/remove_default_ipv4_ippool.dart';
export 'src/steps/remove_existing_cluster_issuer.dart';
export 'src/steps/remove_kubernetes_object.dart';
export 'src/steps/replace_calico_agent_for_pod_cidr.dart';
export 'src/steps/require_pod_cidr_free_of_reserved_ranges.dart';
export 'src/steps/require_unpopulated_cluster_for_pod_cidr_migration.dart';
export 'src/steps/restart_cert_manager_and_reapply_cluster_issuer.dart';
export 'src/steps/set_default_storage_class.dart';
export 'src/steps/verify_ippool_converged_with_self_heal.dart';
export 'src/steps/wait_for_command_output.dart';
export 'src/steps/write_cluster_issuer_manifest.dart';
