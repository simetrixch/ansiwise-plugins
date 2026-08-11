import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/branch/require_installation_domain.dart';
import '../steps/branch/require_master_matches_role.dart';
import '../steps/branch/stamp_app_toggles.dart';
import '../steps/branch/stamp_cluster_profile.dart';
import '../steps/branch/stamp_placeholder_in_tracked_files.dart';
import '../steps/branch/stamp_role.dart';
import '../steps/branch/write_cluster_map.dart';
import '../steps/branch/write_stage_config.dart';
import '../steps/branch/write_stage_secrets.dart';

/// Every step that turns the product trunk into one installation's branch.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
///
/// **The git of this program is not here.** Measuring a committer identity, offering a push that
/// changes nothing and cutting a branch are things git does for anybody, so they are registered by
/// `ansiwise-git` and named by the same program file. What is left here is what only this product
/// can answer: whether the domain it was given is one.
///
/// **`answers:` is what a step reads out of the run rather than out of the program file**, and it is
/// declared here for the same reason `arguments:` is: a step reaching for an answer the program
/// never declared would fail in the middle of an installation, and the resolver refuses that
/// combination before anything is looked at. The list is taken from the step's own `answers`
/// constant, so the entry and the class cannot come to disagree about it.
const Map<StepName, RegisteredStep> branchSteps = <StepName, RegisteredStep>{
  StepName('require_installation_domain'): RegisteredStep(
    name: StepName('require_installation_domain'),
    source: 'lib/src/steps/branch/require_installation_domain.dart:22',
    create: RequireInstallationDomain.fromArguments,
    answers: RequireInstallationDomain.answers,
  ),
  StepName('require_master_matches_role'): RegisteredStep(
    name: StepName('require_master_matches_role'),
    source: 'lib/src/steps/branch/require_master_matches_role.dart:25',
    create: RequireMasterMatchesRole.fromArguments,
    answers: RequireMasterMatchesRole.answers,
  ),
  StepName('stamp_placeholder_in_tracked_files'): RegisteredStep(
    name: StepName('stamp_placeholder_in_tracked_files'),
    source: 'lib/src/steps/branch/stamp_placeholder_in_tracked_files.dart:66',
    create: StampPlaceholderInTrackedFiles.fromArguments,
    arguments: StampPlaceholderInTrackedFiles.arguments,
    answers: StampPlaceholderInTrackedFiles.answers,
  ),
  StepName('write_cluster_map'): RegisteredStep(
    name: StepName('write_cluster_map'),
    source: 'lib/src/steps/branch/write_cluster_map.dart:26',
    create: WriteClusterMap.fromArguments,
    arguments: WriteClusterMap.arguments,
    answers: WriteClusterMap.answers,
  ),
  StepName('write_stage_config'): RegisteredStep(
    name: StepName('write_stage_config'),
    source: 'lib/src/steps/branch/write_stage_config.dart:25',
    create: WriteStageConfig.fromArguments,
    arguments: WriteStageConfig.arguments,
    answers: WriteStageConfig.answers,
  ),
  StepName('write_stage_secrets'): RegisteredStep(
    name: StepName('write_stage_secrets'),
    source: 'lib/src/steps/branch/write_stage_secrets.dart:30',
    create: WriteStageSecrets.fromArguments,
    arguments: WriteStageSecrets.arguments,
    answers: WriteStageSecrets.answers,
  ),
  StepName('stamp_role'): RegisteredStep(
    name: StepName('stamp_role'),
    source: 'lib/src/steps/branch/stamp_role.dart:29',
    create: StampRole.fromArguments,
    arguments: StampRole.arguments,
    answers: StampRole.answers,
  ),
  StepName('stamp_cluster_profile'): RegisteredStep(
    name: StepName('stamp_cluster_profile'),
    source: 'lib/src/steps/branch/stamp_cluster_profile.dart:38',
    create: StampClusterProfile.fromArguments,
    arguments: StampClusterProfile.arguments,
    answers: StampClusterProfile.answers,
  ),
  StepName('stamp_app_toggles'): RegisteredStep(
    name: StepName('stamp_app_toggles'),
    source: 'lib/src/steps/branch/stamp_app_toggles.dart:28',
    create: StampAppToggles.fromArguments,
    arguments: StampAppToggles.arguments,
    answers: StampAppToggles.answers,
  ),
};
