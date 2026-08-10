import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/gitops/argocd_root_app.dart';
import '../steps/gitops/build_plane.dart';
import '../steps/gitops/idp_discovery_reachable.dart';
import '../steps/gitops/kubernetes_secret_from_vault.dart';
import '../steps/gitops/stage_toggle.dart';

/// Every step that puts the platform's own services on top of a standing cluster.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
const Map<StepName, RegisteredStep> gitopsSteps = <StepName, RegisteredStep>{
  StepName('kubernetes_secret_from_vault'): RegisteredStep(
    name: StepName('kubernetes_secret_from_vault'),
    source: 'lib/src/steps/gitops/kubernetes_secret_from_vault.dart:29',
    create: KubernetesSecretFromVault.fromArguments,
    arguments: KubernetesSecretFromVault.arguments,
    answers: KubernetesSecretFromVault.answers,
  ),
  StepName('idp_discovery_reachable'): RegisteredStep(
    name: StepName('idp_discovery_reachable'),
    source: 'lib/src/steps/gitops/idp_discovery_reachable.dart:24',
    create: IdpDiscoveryReachable.fromArguments,
    arguments: IdpDiscoveryReachable.arguments,
    answers: IdpDiscoveryReachable.answers,
  ),
  StepName('argocd_root_app'): RegisteredStep(
    name: StepName('argocd_root_app'),
    source: 'lib/src/steps/gitops/argocd_root_app.dart:22',
    create: ArgocdRootApp.fromArguments,
    arguments: ArgocdRootApp.arguments,
    answers: ArgocdRootApp.answers,
  ),
};

/// Every condition a program of this area may put behind `when:`.
///
/// **These are what an enabled gate is, and there is no other kind.** A part of the platform that is
/// switched off has to leave nothing behind, and the way to be sure of that is to have its steps
/// never run — not to have each of them decide for itself and report success without doing anything,
/// which reads the same in a record. A condition is measured once, before the first step, so the
/// plan an operator sees names each skipped row together with the condition that skipped it.
const Map<PredicateName, RegisteredPredicate>
gitopsPredicates = <PredicateName, RegisteredPredicate>{
  PredicateName('vault_enabled'): RegisteredPredicate(
    name: PredicateName('vault_enabled'),
    source: 'lib/src/steps/gitops/stage_toggle.dart:18',
    predicate: StageToggle(
      key: 'ENABLE_VAULT',
      part: 'the secret store',
      // No default. Bringing up the platform's only secret store, minting its quorum and writing
      // the one file that holds it is not something a cluster gets because nobody said
      // otherwise.
      whenUnset: false,
    ),
    describes: 'whether the stage config of this installation asks for a secret store',
  ),
  PredicateName('idp_enabled'): RegisteredPredicate(
    name: PredicateName('idp_enabled'),
    source: 'lib/src/steps/gitops/stage_toggle.dart:18',
    predicate: StageToggle(
      key: 'ENABLE_IDP',
      part: 'the identity provider',
      // The other way round from the secret store, deliberately: a cluster without an identity
      // provider stands, it simply cannot log anybody in yet, so an installation that says
      // nothing gets one.
      whenUnset: true,
    ),
    describes: 'whether this installation runs an identity provider',
  ),
  PredicateName('argocd_enabled'): RegisteredPredicate(
    name: PredicateName('argocd_enabled'),
    source: 'lib/src/steps/gitops/stage_toggle.dart:18',
    predicate: StageToggle(key: 'ENABLE_ARGOCD', part: 'the reconciler', whenUnset: false),
    describes: 'whether this installation hands its cluster over to a reconciler',
  ),
  PredicateName('build_plane_here'): RegisteredPredicate(
    name: PredicateName('build_plane_here'),
    source: 'lib/src/steps/gitops/build_plane.dart:22',
    predicate: BuildPlane(here: true),
    describes: 'whether the build plane of this installation runs on this cluster',
  ),
  PredicateName('build_plane_elsewhere'): RegisteredPredicate(
    name: PredicateName('build_plane_elsewhere'),
    source: 'lib/src/steps/gitops/build_plane.dart:22',
    predicate: BuildPlane(here: false),
    describes: 'whether the build plane of this installation runs on another cluster',
  ),
};
