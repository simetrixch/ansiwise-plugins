import 'package:ansiwise_core/ansiwise_core.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to judge and prepare a machine: its packages, its
/// snaps, its accounts, its disks, its network and the tools an operator uses on it.
///
/// It knows the TOOLS a machine carries or is given — apt, dpkg, snap, sshd, netplan, nft, ip,
/// systemd, curl, mount and the tailnet client — and nothing of what is being built on it. The
/// last one is named because one step drives it by name, and a tool a step names is a tool this
/// manifest declares. Which snap runs a cluster is not on the list on purpose: it is a product's
/// choice of substrate, so the steps that drive one take every one of its words from the row.
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
