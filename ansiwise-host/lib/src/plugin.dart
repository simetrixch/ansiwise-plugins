import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to judge and prepare a machine: its packages, its snaps, its accounts, its disks, its network and the tools an operator uses on it.
///
/// It knows the TOOLS a machine comes with — apt, snap, sshd, netplan, nft, systemd — and nothing of what is being built on it.
///
/// The name is the one a configuration writes to turn this on, and it is the name of the directory
/// the plugin lives in, so the word in the file and the thing it activates are the same word.
final class HostPlugin implements Plugin {
  /// Creates the plugin.
  const HostPlugin();

  @override
  String get name => 'ansiwise-host';

  @override
  Registry get registry => hostRegistry;
}
