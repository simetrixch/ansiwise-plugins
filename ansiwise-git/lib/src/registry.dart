import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/copy_branch_file.dart';
import 'steps/git_branch.dart';
import 'steps/git_clone.dart';
import 'steps/git_fetch.dart';
import 'steps/git_identity.dart';
import 'steps/git_commit.dart';
import 'steps/git_merge_ref.dart';
import 'steps/git_push.dart';
import 'steps/git_tag.dart';
import 'steps/write_value_in_branch_file.dart';
import 'steps/git_push_credential.dart';
import 'steps/measure_value_in_branch_file.dart';
import 'steps/require_git_identity.dart';
import 'steps/require_pushable_remote.dart';
import 'steps/replace_text_in_tracked_files.dart';
import 'steps/replace_regex_in_tracked_file.dart';
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
  StepName('require_git_identity'): RegisteredStep(
    name: StepName('require_git_identity'),
    source: 'lib/src/steps/require_git_identity.dart:12',
    create: RequireGitIdentity.fromArguments,
    arguments: RequireGitIdentity.arguments,
  ),
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
  StepName('git_clone'): RegisteredStep(
    name: StepName('git_clone'),
    source: 'lib/src/steps/git_clone.dart:32',
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
    source: 'lib/src/steps/git_merge_ref.dart:35',
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
  // Beside the push, because a tag is pushed the moment it is made: a tag that exists in one
  // checkout and nowhere else is a statement nothing else can resolve.
  // Before either of them, in a program that means it: a checkout resolves a remote name to
  // whatever it last saw, and both the tag and the merge below read such a name.
  StepName('git_fetch'): RegisteredStep(
    name: StepName('git_fetch'),
    source: 'lib/src/steps/git_fetch.dart:25',
    create: GitFetch.fromArguments,
    arguments: GitFetch.arguments,
  ),
  StepName('git_tag'): RegisteredStep(
    name: StepName('git_tag'),
    source: 'lib/src/steps/git_tag.dart:22',
    create: GitTag.fromArguments,
    arguments: GitTag.arguments,
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
  StepName('replace_text_in_tracked_files'): RegisteredStep(
    name: StepName('replace_text_in_tracked_files'),
    source: 'lib/src/steps/replace_text_in_tracked_files.dart:10',
    create: ReplaceTextInTrackedFiles.fromArguments,
    arguments: ReplaceTextInTrackedFiles.arguments,
  ),
  StepName('replace_regex_in_tracked_file'): RegisteredStep(
    name: StepName('replace_regex_in_tracked_file'),
    source: 'lib/src/steps/replace_regex_in_tracked_file.dart:7',
    create: ReplaceRegexInTrackedFile.fromArguments,
    arguments: ReplaceRegexInTrackedFile.arguments,
  ),
  StepName('stamp_placeholder_in_tracked_files'): RegisteredStep(
    name: StepName('stamp_placeholder_in_tracked_files'),
    source: 'lib/src/steps/branch/stamp_placeholder_in_tracked_files.dart:78',
    create: StampPlaceholderInTrackedFiles.fromArguments,
    arguments: StampPlaceholderInTrackedFiles.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about one product's state, and that is what this
/// package deliberately knows nothing about.
const Registry gitRegistry = Registry(
  steps: gitSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
