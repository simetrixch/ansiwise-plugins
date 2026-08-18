import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to drive git in one checkout — measure that it can
/// commit, measure that it could push, and cut a branch.
///
/// It knows the TOOL and nothing of any product kept in a checkout — where the checkout stands,
/// which remote it pushes to, which branch a new one is cut from, and which answer the new name is
/// read out of are all arguments a program row fills.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class GitPlugin implements Plugin {
  /// Creates the plugin.
  const GitPlugin();

  @override
  String get name => 'ansiwise-git';

  @override
  Registry get registry => gitRegistry;
}
