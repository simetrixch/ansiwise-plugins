/// Reading the private-network client's own account of this machine, for every step that acts on it.
///
/// **The BACKEND STATE decides membership, never the daemon's presence.** The service runs from the
/// moment the client is installed and belongs to nothing until a credential has been used to join,
/// so "tailscaled is running" proves nothing — only what the client itself reports does. And an
/// empty address cannot tell "on no network" from "could not ask", which is why the readers here
/// have a third answer: null is "the client could not be read", and every step turns that into a
/// blocked check rather than into a guess.
///
/// **Every reading runs as root.** The client talks to its daemon over a root-owned local socket,
/// and these steps run as the login account — asked unelevated, the client answers a permission
/// refusal that reads exactly like "not on any network". Running a reading as root does not make it
/// change anything, so the commands stay observing and a dry run still performs them.
library;

import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// What the client is called. The one name of this family that is the tool's own.
const String tailnetTool = 'tailscale';

/// The backend state the client reports while it is a member of a network.
const String tailnetRunning = 'Running';

/// The backend state the client reports once its node key is gone — logged out, with nothing to
/// come back up with.
const String tailnetNeedsLogin = 'NeedsLogin';

/// The client's backend state, or null when it cannot be read.
///
/// Read from `tailscale status --json` and never from the exit code: the client exits non-zero
/// while it is off a network AND still prints the state, so the exit code alone would read "off"
/// as "unreadable". What makes the answer null is output that is not the client's own JSON — a
/// client that is not installed, or a daemon that is not answering its socket.
Future<String?> tailnetState(StepContext context) async {
  final CommandResult status = await context.shell.run(
    const Command.observing(tailnetTool, arguments: <String>['status', '--json'], elevated: true),
  );
  final Object? decoded = _decoded(status.stdout);
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final Object? state = decoded['BackendState'];
  return state is String && state.isNotEmpty ? state : null;
}

/// This machine's IPv4 address on the network, or null when it holds none that can be read.
///
/// The client lists the addresses of this machine itself under `Self.TailscaleIPs` (and older
/// clients at the top under `TailscaleIPs`); the IPv4 among them is the one everything that dials
/// this machine uses.
Future<String?> tailnetAddress(StepContext context) async {
  final CommandResult status = await context.shell.run(
    const Command.observing(tailnetTool, arguments: <String>['status', '--json'], elevated: true),
  );
  final Object? decoded = _decoded(status.stdout);
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final Object? self = decoded['Self'];
  final Object? addresses = self is Map<String, Object?>
      ? (self['TailscaleIPs'] ?? decoded['TailscaleIPs'])
      : decoded['TailscaleIPs'];
  if (addresses is! List<Object?>) {
    return null;
  }
  for (final Object? address in addresses) {
    if (address is String && !address.contains(':')) {
      return address;
    }
  }
  return null;
}

/// The coordinator this machine's client is logged in to, or the empty string when it cannot be
/// read.
///
/// `tailscale status` does not carry it — the client keeps it in its own preferences — and without
/// it a machine on somebody else's network is indistinguishable from one on ours: both report
/// Running. The trailing slash is stripped so the two spellings of one address compare equal.
Future<String> tailnetLoginServer(StepContext context) async {
  final CommandResult prefs = await context.shell.run(
    const Command.observing(tailnetTool, arguments: <String>['debug', 'prefs'], elevated: true),
  );
  final Object? decoded = _decoded(prefs.stdout);
  if (decoded is! Map<String, Object?>) {
    return '';
  }
  final Object? url = decoded['ControlURL'];
  return url is String ? tailnetCoordinatorSpelling(url) : '';
}

/// [url] as one canonical spelling — the trailing slash removed — so the address the client holds
/// and the address a run was told compare equal however either was written.
String tailnetCoordinatorSpelling(String url) =>
    url.endsWith('/') ? url.substring(0, url.length - 1) : url;

/// [text] as JSON, or null when it is not.
Object? _decoded(String text) {
  if (text.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// One line describing the client's state for a check verdict, so every step of this family says
/// it the same way.
String tailnetStateLine(String? state) =>
    state == null ? 'the client could not be read' : 'client state: $state';
