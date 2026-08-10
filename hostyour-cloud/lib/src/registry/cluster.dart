import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/cluster/configure_kube_apiserver_oidc.dart';
import '../steps/cluster/preflight_docker_mirror_credential.dart';
import '../steps/cluster/restart_microk8s_snap_for_pod_cidr.dart';
import '../steps/cluster/write_containerd_docker_mirror.dart';

/// Every step that turns a prepared machine into a cluster the platform can be deployed onto and
/// that no tool package carries yet.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
///
/// **WHAT IS NO LONGER HERE MATTERS AS MUCH AS WHAT IS.** The addons, the pod range stamped into the
/// network manifest and the rendered certificate issuer are capabilities of the machine and of the
/// cluster, and they live in `ansiwise-host` and `ansiwise-kubernetes` now. What is left is what
/// still knows something only THIS product could tell it: the checkout its profile and its secrets
/// stand in, and the shape of the address its identity provider issues at.
///
/// The entries are written in the order the program runs them, and that order is itself a
/// constraint: the pod range before any pod is given an address, the image mirror before any image
/// is pulled, and who the API server accepts after the addons that installed it are on.
const Map<StepName, RegisteredStep> clusterSteps = <StepName, RegisteredStep>{
  StepName('restart_microk8s_snap_for_pod_cidr'): RegisteredStep(
    name: StepName('restart_microk8s_snap_for_pod_cidr'),
    source: 'lib/src/steps/cluster/restart_microk8s_snap_for_pod_cidr.dart:21',
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
  StepName('configure_kube_apiserver_oidc'): RegisteredStep(
    name: StepName('configure_kube_apiserver_oidc'),
    source: 'lib/src/steps/cluster/configure_kube_apiserver_oidc.dart:16',
    create: ConfigureKubeApiserverOidc.fromArguments,
    arguments: ConfigureKubeApiserverOidc.arguments,
    answers: ConfigureKubeApiserverOidc.answers,
  ),
};
