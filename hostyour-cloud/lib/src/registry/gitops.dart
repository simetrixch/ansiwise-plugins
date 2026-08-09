import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/gitops/argocd_root_app.dart';
import '../steps/gitops/build_plane.dart';
import '../steps/gitops/helm_release.dart';
import '../steps/gitops/helm_repository.dart';
import '../steps/gitops/idp_discovery_reachable.dart';
import '../steps/gitops/kubernetes_configmap_from_directory.dart';
import '../steps/gitops/kubernetes_namespace.dart';
import '../steps/gitops/kubernetes_object.dart';
import '../steps/gitops/kubernetes_secret_from_vault.dart';
import '../steps/gitops/oidc_admins_binding.dart';
import '../steps/gitops/stage_toggle.dart';
import '../steps/gitops/vault_auth_method.dart';
import '../steps/gitops/vault_auth_role.dart';
import '../steps/gitops/vault_init.dart';
import '../steps/gitops/vault_kv_entry.dart';
import '../steps/gitops/vault_kv_mount.dart';
import '../steps/gitops/vault_policy.dart';
import '../steps/gitops/vault_unsealed.dart';

/// Every step that puts the platform's own services on top of a standing cluster.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
const Map<StepName, RegisteredStep> gitopsSteps = <StepName, RegisteredStep>{
  StepName('helm_repository'): RegisteredStep(
    name: StepName('helm_repository'),
    source: 'lib/src/steps/gitops/helm_repository.dart:15',
    create: HelmRepository.fromArguments,
    arguments: HelmRepository.arguments,
  ),
  StepName('kubernetes_namespace'): RegisteredStep(
    name: StepName('kubernetes_namespace'),
    source: 'lib/src/steps/gitops/kubernetes_namespace.dart:15',
    create: KubernetesNamespace.fromArguments,
    arguments: KubernetesNamespace.arguments,
  ),
  StepName('kubernetes_configmap_from_directory'): RegisteredStep(
    name: StepName('kubernetes_configmap_from_directory'),
    source: 'lib/src/steps/gitops/kubernetes_configmap_from_directory.dart:23',
    create: KubernetesConfigmapFromDirectory.fromArguments,
    arguments: KubernetesConfigmapFromDirectory.arguments,
  ),
  StepName('kubernetes_object'): RegisteredStep(
    name: StepName('kubernetes_object'),
    source: 'lib/src/steps/gitops/kubernetes_object.dart:26',
    create: KubernetesObject.fromArguments,
    arguments: KubernetesObject.arguments,
  ),
  StepName('kubernetes_secret_from_vault'): RegisteredStep(
    name: StepName('kubernetes_secret_from_vault'),
    source: 'lib/src/steps/gitops/kubernetes_secret_from_vault.dart:30',
    create: KubernetesSecretFromVault.fromArguments,
    arguments: KubernetesSecretFromVault.arguments,
    answers: KubernetesSecretFromVault.answers,
  ),
  StepName('helm_release'): RegisteredStep(
    name: StepName('helm_release'),
    source: 'lib/src/steps/gitops/helm_release.dart:23',
    create: HelmRelease.fromArguments,
    arguments: HelmRelease.arguments,
  ),
  StepName('vault_init'): RegisteredStep(
    name: StepName('vault_init'),
    source: 'lib/src/steps/gitops/vault_init.dart:31',
    create: VaultInit.fromArguments,
    arguments: VaultInit.arguments,
    answers: VaultInit.answers,
  ),
  StepName('vault_unsealed'): RegisteredStep(
    name: StepName('vault_unsealed'),
    source: 'lib/src/steps/gitops/vault_unsealed.dart:19',
    create: VaultUnsealed.fromArguments,
    arguments: VaultUnsealed.arguments,
    answers: VaultUnsealed.answers,
  ),
  StepName('vault_kv_mount'): RegisteredStep(
    name: StepName('vault_kv_mount'),
    source: 'lib/src/steps/gitops/vault_kv_mount.dart:14',
    create: VaultKvMount.fromArguments,
    arguments: VaultKvMount.arguments,
    answers: VaultKvMount.answers,
  ),
  StepName('vault_auth_method'): RegisteredStep(
    name: StepName('vault_auth_method'),
    source: 'lib/src/steps/gitops/vault_auth_method.dart:23',
    create: VaultAuthMethod.fromArguments,
    arguments: VaultAuthMethod.arguments,
    answers: VaultAuthMethod.answers,
  ),
  StepName('vault_policy'): RegisteredStep(
    name: StepName('vault_policy'),
    source: 'lib/src/steps/gitops/vault_policy.dart:33',
    create: VaultPolicy.fromArguments,
    arguments: VaultPolicy.arguments,
    answers: VaultPolicy.answers,
  ),
  StepName('vault_auth_role'): RegisteredStep(
    name: StepName('vault_auth_role'),
    source: 'lib/src/steps/gitops/vault_auth_role.dart:24',
    create: VaultAuthRole.fromArguments,
    arguments: VaultAuthRole.arguments,
    answers: VaultAuthRole.answers,
  ),
  StepName('vault_kv_entry'): RegisteredStep(
    name: StepName('vault_kv_entry'),
    source: 'lib/src/steps/gitops/vault_kv_entry.dart:28',
    create: VaultKvEntry.fromArguments,
    arguments: VaultKvEntry.arguments,
    answers: VaultKvEntry.answers,
  ),
  StepName('idp_discovery_reachable'): RegisteredStep(
    name: StepName('idp_discovery_reachable'),
    source: 'lib/src/steps/gitops/idp_discovery_reachable.dart:24',
    create: IdpDiscoveryReachable.fromArguments,
    arguments: IdpDiscoveryReachable.arguments,
    answers: IdpDiscoveryReachable.answers,
  ),
  StepName('oidc_admins_binding'): RegisteredStep(
    name: StepName('oidc_admins_binding'),
    source: 'lib/src/steps/gitops/oidc_admins_binding.dart:19',
    create: OidcAdminsBinding.fromArguments,
    arguments: OidcAdminsBinding.arguments,
  ),
  StepName('argocd_root_app'): RegisteredStep(
    name: StepName('argocd_root_app'),
    source: 'lib/src/steps/gitops/argocd_root_app.dart:21',
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
