import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to drive a Vault: mint its quorum, unseal it, mount a store, enable an auth method, and write policies, roles and entries.
///
/// It knows the TOOL and never a product kept in it. Where the address and the credential stand, and under which names, are arguments — so a product that keeps the same facts somewhere else writes its own paths into a row instead of forking these steps.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class VaultPlugin implements Plugin {
  /// Creates the plugin.
  const VaultPlugin();

  @override
  String get name => 'ansiwise-vault';

  @override
  Registry get registry => vaultRegistry;
}
