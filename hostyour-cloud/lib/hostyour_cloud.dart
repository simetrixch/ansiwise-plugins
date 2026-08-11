/// What should happen to a machine that becomes a hostyour-cloud installation.
///
/// This package knows the platform. The framework it runs on knows none of it, and a check
/// turns the tree red if that ever stops being true.
library;

export 'src/branch/fqdn_selection.dart';
export 'src/branch/role_pruning.dart';
export 'src/plugin.dart';
export 'src/plugins.dart';
export 'src/registry.dart';
export 'src/registry/branch.dart';
export 'src/registry/cluster.dart';
export 'src/registry/gitops.dart';
export 'src/steps/branch/filled_template.dart';
export 'src/steps/branch/master_part.dart';
export 'src/steps/branch/require_installation_domain.dart';
export 'src/steps/branch/require_master_matches_role.dart';
export 'src/steps/branch/stamp_app_toggles.dart';
export 'src/steps/branch/stamp_cluster_profile.dart';
export 'src/steps/branch/stamp_placeholder_in_tracked_files.dart';
export 'src/steps/branch/stamp_role.dart';
export 'src/steps/branch/write_cluster_map.dart';
export 'src/steps/branch/write_stage_config.dart';
export 'src/steps/branch/write_stage_secrets.dart';
export 'src/steps/cluster/configure_kube_apiserver_oidc.dart';
export 'src/steps/cluster/microk8s.dart';
export 'src/steps/cluster/restart_microk8s_snap_for_pod_cidr.dart';
export 'src/steps/gitops/build_plane.dart';
export 'src/steps/gitops/idp_discovery_reachable.dart';
export 'src/steps/gitops/stage_config.dart';
export 'src/steps/gitops/stage_toggle.dart';
