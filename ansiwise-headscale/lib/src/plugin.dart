import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how a private network's coordinator is driven.
///
/// It knows the coordinator's own grammar — users, pre-auth keys, single use and expiry — and how
/// to keep a credential off every surface that outlives it. It knows no application of that: how
/// the admin surface is reached, which machine gets a user, and where a minted credential is put
/// for the caller are all said by a program row.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class HeadscalePlugin implements Plugin {
  /// Creates the plugin.
  const HeadscalePlugin();

  @override
  String get name => 'ansiwise-headscale';

  @override
  Registry get registry => headscaleRegistry;
}
