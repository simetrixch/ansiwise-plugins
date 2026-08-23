/// Steps that drive git in one checkout: what has to be true before a commit, what has to be true
/// before a push, and cutting a branch.
///
/// This package knows the tool and never an application of it. Which checkout, which remote, which
/// branch is cut from which, and where the name of a new branch is read from — all of that is a
/// program row's to say.
library;

export 'src/registry.dart';
export 'src/steps/copy_branch_file.dart';
export 'src/steps/git_branch.dart';
export 'src/steps/git_clone.dart';
export 'src/steps/git_identity.dart';
export 'src/steps/git_commit.dart';
export 'src/steps/git_merge_ref.dart';
export 'src/steps/git_push.dart';
export 'src/steps/git_push_credential.dart';
export 'src/steps/measure_value_in_branch_file.dart';
export 'src/steps/require_git_identity.dart';
export 'src/steps/require_pushable_remote.dart';
export 'src/steps/branch/stamp_placeholder_in_tracked_files.dart';
export 'src/steps/branch/stamp_selection.dart';
export 'src/plugin.dart';
