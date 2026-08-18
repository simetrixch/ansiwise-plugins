import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to drive a Kubernetes cluster through kubectl.
///
/// It knows the TOOL and never an application of it. The names it carries — kube-system,
/// cert-manager, default-ipv4-ippool, calico-node — are names those tools gave themselves, the same
/// on every cluster. Everything one installation decides — how kubectl is invoked, which paths,
/// which issuer name, which prefix — is an argument its program rows fill.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class KubernetesPlugin implements Plugin {
  /// Creates the plugin.
  const KubernetesPlugin();

  @override
  String get name => 'ansiwise-kubernetes';

  @override
  Registry get registry => kubernetesRegistry;
}
