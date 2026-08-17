import 'package:ansiwise_api/ansiwise_api.dart';

import 'steps/git_branch.dart';
import 'steps/git_commit.dart';
import 'steps/git_push.dart';
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
/// **No entry declares an answer, and one step reads one.** `git_branch` is told by its row WHICH
/// answer holds the branch name, so the name is a value at run time and not a constant a registry
/// entry could carry. The resolver's refusal for an answer a program never declared therefore
/// cannot reach it, and the step refuses the same case itself, naming the answer its row pointed at.
const Map<StepName, RegisteredStep> gitSteps = <StepName, RegisteredStep>{
  StepName('require_git_identity'): RegisteredStep(
    name: StepName('require_git_identity'),
    source: 'lib/src/steps/require_git_identity.dart:12',
    create: RequireGitIdentity.fromArguments,
    arguments: RequireGitIdentity.arguments,
  ),
  StepName('require_pushable_remote'): RegisteredStep(
    name: StepName('require_pushable_remote'),
    source: 'lib/src/steps/require_pushable_remote.dart:18',
    create: RequirePushableRemote.fromArguments,
    arguments: RequirePushableRemote.arguments,
  ),
  StepName('git_branch'): RegisteredStep(
    name: StepName('git_branch'),
    source: 'lib/src/steps/git_branch.dart:20',
    create: GitBranch.fromArguments,
    arguments: GitBranch.arguments,
  ),
  StepName('git_commit'): RegisteredStep(
    name: StepName('git_commit'),
    source: 'lib/src/steps/git_commit.dart:20',
    create: GitCommit.fromArguments,
    arguments: GitCommit.arguments,
  ),
  StepName('git_push'): RegisteredStep(
    name: StepName('git_push'),
    source: 'lib/src/steps/git_push.dart:19',
    create: GitPush.fromArguments,
    arguments: GitPush.arguments,
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
    source: 'lib/src/steps/branch/stamp_placeholder_in_tracked_files.dart:66',
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
