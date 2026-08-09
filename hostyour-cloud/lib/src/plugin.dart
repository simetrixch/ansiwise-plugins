import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to turn a machine into a hostyour-cloud installation.
///
/// The framework knows none of it. Every word that is specific to this platform — microk8s, Vault,
/// ArgoCD, Cloudflare, helm, snap — lives on this side of the boundary, and a check turns the tree
/// red if one appears on the other.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the repository
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class HostyourCloudPlugin implements Plugin {
  /// Creates the plugin.
  const HostyourCloudPlugin();

  @override
  String get name => 'hostyour-cloud';

  @override
  Registry get registry => executionRegistry;
}
