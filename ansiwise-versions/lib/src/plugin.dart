import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how one declaration of pinned component versions is
/// held against the files that carry each pin, and against what each upstream has published.
///
/// It knows the TOOLS — the declaration's own grammar, a chart and its repository index, a
/// container build file, the tag lists of registries, the public release feeds — and nothing of
/// any product measured with them. Which components exist, where each pin is written and where
/// each upstream lives all stand in the declaration file a program row points at.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class VersionsPlugin implements Plugin {
  /// Creates the plugin.
  const VersionsPlugin();

  @override
  String get name => 'ansiwise-versions';

  @override
  Registry get registry => versionsRegistry;
}
