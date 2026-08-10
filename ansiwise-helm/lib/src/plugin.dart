import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to drive helm: make a chart repository known, and converge one release onto a cluster.
///
/// It knows the TOOL and nothing of any product deployed with it — the repository name and address, the release, the chart, its version, the namespace and the values are all arguments a program row fills.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class HelmPlugin implements Plugin {
  /// Creates the plugin.
  const HelmPlugin();

  @override
  String get name => 'ansiwise-helm';

  @override
  Registry get registry => helmRegistry;
}
