import 'package:ansiwise_api/ansiwise_api.dart';
import '../steps/branch/create_install_branch.dart';
import '../steps/branch/require_git_identity.dart';
import '../steps/branch/require_pushable_origin.dart';
import '../steps/branch/stamp_app_toggles.dart';
import '../steps/branch/stamp_cluster_profile.dart';
import '../steps/branch/stamp_placeholder_in_tracked_files.dart';
import '../steps/branch/stamp_role.dart';
import '../steps/branch/write_cluster_map.dart';
import '../steps/branch/write_stage_config.dart';
import '../steps/branch/write_stage_mail_dns.dart';
import '../steps/branch/write_stage_secrets.dart';

/// Every step that turns the product trunk into one installation's branch.
///
/// One file per area rather than one growing file, so two areas can be written at the same time
/// without meeting in the same place. The composer in the parent directory is the only thing that
/// knows about all of them.
///
/// **`answers:` is what a step reads out of the run rather than out of the program file**, and it is
/// declared here for the same reason `arguments:` is: a step reaching for an answer the program
/// never declared would fail in the middle of an installation, and the resolver refuses that
/// combination before anything is looked at. The list is taken from the step's own `answers`
/// constant, so the entry and the class cannot come to disagree about it.
const Map<StepName, RegisteredStep> branchSteps = <StepName, RegisteredStep>{
  StepName('require_git_identity'): RegisteredStep(
    name: StepName('require_git_identity'),
    source: 'lib/src/steps/branch/require_git_identity.dart:12',
    create: RequireGitIdentity.fromArguments,
    arguments: RequireGitIdentity.arguments,
  ),
  StepName('require_pushable_origin'): RegisteredStep(
    name: StepName('require_pushable_origin'),
    source: 'lib/src/steps/branch/require_pushable_origin.dart:18',
    create: RequirePushableOrigin.fromArguments,
    arguments: RequirePushableOrigin.arguments,
  ),
  StepName('create_install_branch'): RegisteredStep(
    name: StepName('create_install_branch'),
    source: 'lib/src/steps/branch/create_install_branch.dart:17',
    create: CreateInstallBranch.fromArguments,
    arguments: CreateInstallBranch.arguments,
    answers: CreateInstallBranch.answers,
  ),
  StepName('stamp_placeholder_in_tracked_files'): RegisteredStep(
    name: StepName('stamp_placeholder_in_tracked_files'),
    source: 'lib/src/steps/branch/stamp_placeholder_in_tracked_files.dart:60',
    create: StampPlaceholderInTrackedFiles.fromArguments,
    arguments: StampPlaceholderInTrackedFiles.arguments,
    answers: StampPlaceholderInTrackedFiles.answers,
  ),
  StepName('write_cluster_map'): RegisteredStep(
    name: StepName('write_cluster_map'),
    source: 'lib/src/steps/branch/write_cluster_map.dart:25',
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
  StepName('write_stage_mail_dns'): RegisteredStep(
    name: StepName('write_stage_mail_dns'),
    source: 'lib/src/steps/branch/write_stage_mail_dns.dart:29',
    create: WriteStageMailDns.fromArguments,
    arguments: WriteStageMailDns.arguments,
    answers: WriteStageMailDns.answers,
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
    source: 'lib/src/steps/branch/stamp_cluster_profile.dart:25',
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
