import 'package:ansiwise_core/ansiwise_core.dart';

import 'conditions/remote_has_branch.dart';
import 'steps/copy_branch_file.dart';
import 'steps/delete_local_branch.dart';
import 'steps/git_branch.dart';
import 'steps/git_checkout_branch.dart';
import 'steps/git_clone.dart';
import 'steps/git_fetch.dart';
import 'steps/git_identity.dart';
import 'steps/git_commit.dart';
import 'steps/git_merge_ref.dart';
import 'steps/git_push.dart';
import 'steps/write_value_in_branch_file.dart';
import 'steps/git_push_credential.dart';
import 'steps/measure_value_in_branch_file.dart';
import 'steps/require_pushable_remote.dart';
import 'steps/branch/stamp_placeholder_in_tracked_files.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
///
/// **No entry declares an answer, and several steps read one.** `git_branch`, `git_merge_ref` and
/// their siblings are each told by their row WHICH answer holds the name they need, so the name is a
/// value at run time and not a constant a registry entry could carry. The resolver's refusal for an
/// answer a program never declared therefore cannot reach them, and each step refuses the same case
/// itself, naming the answer its row pointed at.
const Map<StepName, RegisteredStep> gitSteps = <StepName, RegisteredStep>{
  StepName('require_pushable_remote'): RegisteredStep(
    name: StepName('require_pushable_remote'),
    source: 'lib/src/steps/require_pushable_remote.dart:25',
    create: RequirePushableRemote.fromArguments,
    arguments: RequirePushableRemote.arguments,
  ),
  StepName('git_identity'): RegisteredStep(
    name: StepName('git_identity'),
    source: 'lib/src/steps/git_identity.dart:24',
    create: GitIdentity.fromArguments,
    arguments: GitIdentity.arguments,
  ),
  StepName('git_branch'): RegisteredStep(
    name: StepName('git_branch'),
    source: 'lib/src/steps/git_branch.dart:20',
    create: GitBranch.fromArguments,
    arguments: GitBranch.arguments,
  ),
  // Beside git_branch, because the two are the halves of one question a program asks about a
  // branch: cut the name where the remote publishes none, stand on it where it does. Which half a
  // row runs is decided by the condition below, before the first step.
  StepName('git_checkout_branch'): RegisteredStep(
    name: StepName('git_checkout_branch'),
    source: 'lib/src/steps/git_checkout_branch.dart:27',
    create: GitCheckoutBranch.fromArguments,
    arguments: GitCheckoutBranch.arguments,
  ),
  // The third act on a branch name: taking the local one away, so the next run cuts the branch
  // again from what the program says today rather than resuming an attempt nobody can describe.
  StepName('delete_local_branch'): RegisteredStep(
    name: StepName('delete_local_branch'),
    source: 'lib/src/steps/delete_local_branch.dart:23',
    create: DeleteLocalBranch.fromArguments,
    arguments: DeleteLocalBranch.arguments,
  ),
  StepName('git_clone'): RegisteredStep(
    name: StepName('git_clone'),
    source: 'lib/src/steps/git_clone.dart:38',
    create: GitClone.fromArguments,
    arguments: GitClone.arguments,
  ),
  StepName('measure_value_in_branch_file'): RegisteredStep(
    name: StepName('measure_value_in_branch_file'),
    source: 'lib/src/steps/measure_value_in_branch_file.dart:48',
    create: MeasureValueInBranchFile.fromArguments,
    arguments: MeasureValueInBranchFile.arguments,
    publishes: MeasureValueInBranchFile.publishes,
  ),
  StepName('copy_branch_file'): RegisteredStep(
    name: StepName('copy_branch_file'),
    source: 'lib/src/steps/copy_branch_file.dart:28',
    create: CopyBranchFile.fromArguments,
    arguments: CopyBranchFile.arguments,
  ),
  StepName('git_merge_ref'): RegisteredStep(
    name: StepName('git_merge_ref'),
    source: 'lib/src/steps/git_merge_ref.dart:36',
    create: GitMergeRef.fromArguments,
    arguments: GitMergeRef.arguments,
  ),
  StepName('git_commit'): RegisteredStep(
    name: StepName('git_commit'),
    source: 'lib/src/steps/git_commit.dart:34',
    create: GitCommit.fromArguments,
    arguments: GitCommit.arguments,
  ),
  StepName('git_push'): RegisteredStep(
    name: StepName('git_push'),
    source: 'lib/src/steps/git_push.dart:25',
    create: GitPush.fromArguments,
    arguments: GitPush.arguments,
  ),
  // Before the push, in a program that means it: a checkout resolves a remote name to whatever it
  // last saw, and the merge reads such a name.
  StepName('git_fetch'): RegisteredStep(
    name: StepName('git_fetch'),
    source: 'lib/src/steps/git_fetch.dart:25',
    create: GitFetch.fromArguments,
    arguments: GitFetch.arguments,
  ),
  // The writing half of measure_value_in_branch_file, and registered as its mirror: what one reads,
  // the other writes, so a value recorded by one operation and read by the next cannot come to be
  // two different ideas of where it lives.
  StepName('write_value_in_branch_file'): RegisteredStep(
    name: StepName('write_value_in_branch_file'),
    source: 'lib/src/steps/write_value_in_branch_file.dart:24',
    create: WriteValueInBranchFile.fromArguments,
    arguments: WriteValueInBranchFile.arguments,
  ),
  // Directly after the push, because the two are written together in a program: this is what the
  // push's own doc means by the helper it says is arranged before any program runs.
  StepName('git_push_credential'): RegisteredStep(
    name: StepName('git_push_credential'),
    source: 'lib/src/steps/git_push_credential.dart:35',
    create: GitPushCredential.fromArguments,
    arguments: GitPushCredential.arguments,
  ),
  StepName('stamp_placeholder_in_tracked_files'): RegisteredStep(
    name: StepName('stamp_placeholder_in_tracked_files'),
    source: 'lib/src/steps/branch/stamp_placeholder_in_tracked_files.dart:86',
    create: StampPlaceholderInTrackedFiles.fromArguments,
    arguments: StampPlaceholderInTrackedFiles.arguments,
  ),
};

/// Every condition this plugin contributes, keyed by the name a program row writes behind `when:`.
///
/// **What is registered is a reading of the TOOL, and what it is pointed at is the installation's.**
/// A condition asking git what a remote publishes is git's own question and nothing about any
/// product. Which checkout it is asked from, which remote, and which answer holds the branch name
/// are one installation's, so they are stated on that installation's own configuration under
/// `conditions:` and the framework binds them onto this entry under the name it chose there.
///
/// **TWO NAMES OVER ONE READING, and a program row still writes one bare word.** A program acts
/// both ways on a branch: it stands the checkout on one the remote already publishes, and it cuts
/// one the remote does not. Written as `not:` behind `when:` the second would be an operator, and an
/// operator is where a program file starts being a language.
const Map<PredicateName, RegisteredPredicate> gitConditions = <PredicateName, RegisteredPredicate>{
  PredicateName('remote_has_branch'): RegisteredPredicate.taking(
    name: PredicateName('remote_has_branch'),
    source: 'lib/src/conditions/remote_has_branch.dart:34',
    create: RemoteHasBranch.carrying,
    describes: 'whether a remote publishes the branch this run names',
    arguments: RemoteHasBranch.arguments,
  ),
  PredicateName('remote_lacks_branch'): RegisteredPredicate.taking(
    name: PredicateName('remote_lacks_branch'),
    source: 'lib/src/conditions/remote_has_branch.dart:34',
    create: RemoteHasBranch.lacking,
    describes: 'whether a remote publishes no branch of the name this run holds',
    arguments: RemoteHasBranch.arguments,
  ),
};

/// Everything this plugin teaches the framework.
const Registry gitRegistry = Registry(steps: gitSteps, predicates: gitConditions);
