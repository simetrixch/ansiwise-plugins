import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/cluster/restart_microk8s_snap_for_pod_cidr.dart';

/// Every step that turns a prepared machine into a cluster the platform can be deployed onto and
/// that no tool package carries yet.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
///
/// **WHAT IS NO LONGER HERE MATTERS AS MUCH AS WHAT IS.** The addons, the pod range stamped into the
/// network manifest, the rendered certificate issuer and the image mirror are capabilities of the
/// machine and of the cluster, and they live in `ansiwise-host` and `ansiwise-kubernetes` now. What
/// is left is what still knows something only THIS product could tell it: the shape of the address
/// its identity provider issues at, and the rule that decides which cluster of an installation
/// issues it.
///
/// The entries are written in the order the program runs them, and that order is itself a
/// constraint: the pod range before any pod is given an address, and who the API server accepts
/// after the addons that installed it are on.
const Map<StepName, RegisteredStep> clusterSteps = <StepName, RegisteredStep>{
  StepName('restart_microk8s_snap_for_pod_cidr'): RegisteredStep(
    name: StepName('restart_microk8s_snap_for_pod_cidr'),
    source: 'lib/src/steps/cluster/restart_microk8s_snap_for_pod_cidr.dart:21',
    create: RestartMicrok8sSnapForPodCidr.fromArguments,
    arguments: RestartMicrok8sSnapForPodCidr.arguments,
  ),
};
