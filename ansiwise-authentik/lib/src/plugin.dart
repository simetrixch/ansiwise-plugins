import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: the shapes an authentik identity provider defines for
/// itself.
///
/// It knows the TOOL and nothing of any product that logs in through it. Which applications exist,
/// what the provider registered them as, which label it is served under and on which domain are all
/// arguments a program row fills.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class AuthentikPlugin implements Plugin {
  /// Creates the plugin.
  const AuthentikPlugin();

  @override
  String get name => 'ansiwise-authentik';

  @override
  Registry get registry => authentikRegistry;
}
