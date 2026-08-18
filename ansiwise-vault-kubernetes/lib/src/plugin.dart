import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to get one value out of Vault onto a cluster.
///
/// It knows BOTH tools — how Vault answers over its HTTP API and how kubectl is invoked — and that
/// is the whole reason it is a package of its own. A step that reads from one tool and writes to the
/// other cannot be split into two rows, and putting it inside either tool package would make every
/// user of that tool resolve the other one.
///
/// It knows no application of either. Which mount, which entry, which Secret, which namespace,
/// which keys and where the store's own facts stand are arguments a program row fills, and not one
/// of them has a default here.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class VaultKubernetesPlugin implements Plugin {
  /// Creates the plugin.
  const VaultKubernetesPlugin();

  @override
  String get name => 'ansiwise-vault-kubernetes';

  @override
  Registry get registry => vaultKubernetesRegistry;
}
