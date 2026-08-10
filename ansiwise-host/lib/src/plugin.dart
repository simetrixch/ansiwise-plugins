import 'package:ansiwise_api/ansiwise_api.dart';

import 'registry.dart';

/// What this plugin teaches the framework: how to judge and prepare a machine: its packages, its
/// snaps, its accounts, its disks, its network and the tools an operator uses on it.
///
/// It knows the TOOLS a machine carries or is given — apt, dpkg, snap, sshd, netplan, nft, ip,
/// systemd, curl, mount, the MicroK8s snap and the tailnet client — and nothing of what is being
/// built on it. The last two are named because two steps drive them by name, and a tool a step
/// names is a tool this manifest declares: the word list of this package exempts a tool it declares
/// and nothing else, so a step naming one that is missing here would be exempt on the strength of a
/// sentence that is not written.
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
