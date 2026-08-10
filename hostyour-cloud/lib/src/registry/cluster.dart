import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/cluster/configure_kube_apiserver_oidc.dart';
import '../steps/cluster/configure_slave_apiserver_oidc_trust.dart';
import '../steps/cluster/disable_addons.dart';
import '../steps/cluster/enable_addons.dart';
import '../steps/cluster/preflight_docker_mirror_credential.dart';
import '../steps/cluster/restart_microk8s_snap_for_pod_cidr.dart';
import '../steps/cluster/stamp_calico_pool_cidr_in_cni_manifest.dart';
import '../steps/cluster/wait_for_addons_enabled.dart';
import '../steps/cluster/write_cluster_issuer_manifest.dart';
import '../steps/cluster/write_containerd_docker_mirror.dart';

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
  StepName('stamp_calico_pool_cidr_in_cni_manifest'): RegisteredStep(
    name: StepName('stamp_calico_pool_cidr_in_cni_manifest'),
    source: 'lib/src/steps/cluster/stamp_calico_pool_cidr_in_cni_manifest.dart:19',
    create: StampCalicoPoolCidrInCniManifest.fromArguments,
    arguments: StampCalicoPoolCidrInCniManifest.arguments,
  ),
  StepName('restart_microk8s_snap_for_pod_cidr'): RegisteredStep(
    name: StepName('restart_microk8s_snap_for_pod_cidr'),
    source: 'lib/src/steps/cluster/restart_microk8s_snap_for_pod_cidr.dart:18',
    create: RestartMicrok8sSnapForPodCidr.fromArguments,
    arguments: RestartMicrok8sSnapForPodCidr.arguments,
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
  StepName('enable_addons'): RegisteredStep(
    name: StepName('enable_addons'),
    source: 'lib/src/steps/cluster/enable_addons.dart:35',
    create: EnableAddons.fromArguments,
    arguments: EnableAddons.arguments,
  ),
  StepName('wait_for_addons_enabled'): RegisteredStep(
    name: StepName('wait_for_addons_enabled'),
    source: 'lib/src/steps/cluster/wait_for_addons_enabled.dart:20',
    create: WaitForAddonsEnabled.fromArguments,
    arguments: WaitForAddonsEnabled.arguments,
  ),
  StepName('disable_addons'): RegisteredStep(
    name: StepName('disable_addons'),
    source: 'lib/src/steps/cluster/disable_addons.dart:17',
    create: DisableAddons.fromArguments,
    arguments: DisableAddons.arguments,
  ),
  StepName('configure_kube_apiserver_oidc'): RegisteredStep(
    name: StepName('configure_kube_apiserver_oidc'),
    source: 'lib/src/steps/cluster/configure_kube_apiserver_oidc.dart:16',
    create: ConfigureKubeApiserverOidc.fromArguments,
    arguments: ConfigureKubeApiserverOidc.arguments,
    answers: ConfigureKubeApiserverOidc.answers,
  ),
  StepName('configure_slave_apiserver_oidc_trust'): RegisteredStep(
    name: StepName('configure_slave_apiserver_oidc_trust'),
    source: 'lib/src/steps/cluster/configure_slave_apiserver_oidc_trust.dart:20',
    create: ConfigureSlaveApiserverOidcTrust.fromArguments,
    arguments: ConfigureSlaveApiserverOidcTrust.arguments,
    answers: ConfigureSlaveApiserverOidcTrust.answers,
  ),
  StepName('write_cluster_issuer_manifest'): RegisteredStep(
    name: StepName('write_cluster_issuer_manifest'),
    source: 'lib/src/steps/cluster/write_cluster_issuer_manifest.dart:14',
    create: WriteClusterIssuerManifest.fromArguments,
    arguments: WriteClusterIssuerManifest.arguments,
    answers: WriteClusterIssuerManifest.answers,
  ),
};
