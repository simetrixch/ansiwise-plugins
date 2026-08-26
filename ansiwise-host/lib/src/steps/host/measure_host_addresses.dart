import 'package:ansiwise_core/ansiwise_core.dart';

/// The addresses this machine can be reached at, as the ranges something else has to name.
///
/// **WHAT ASKS FOR THIS.** A boundary drawn in address terms — a firewall rule, a network policy —
/// has to name the machine it is drawn around, and a cloud machine's own address is a PUBLIC address.
/// A boundary that carves out the private ranges and calls the rest of the world outside leaves the
/// machine itself inside the allowed part: everything listening on a node address stays reachable
/// from within whatever the boundary was meant to contain. Nothing about that is a fact anybody can
/// write down in advance, because it is different on every machine.
///
/// **AND NOBODY TYPES IT.** A machine's own address is a fact about that machine, and the machine is
/// standing right here. An answer would put the operator between two things they cannot both see —
/// the file the boundary is rendered from, and the interfaces of a host they may never log in to —
/// and one mistyped octet is a boundary that reports itself closed while standing open.
///
/// **EVERY ADDRESS, AS /32 AND NOT AS THE PREFIX IT WAS CONFIGURED WITH.** What is wanted is the
/// machine, not the network it sits in: a node configured `10.1.1.7/24` shares that /24 with every
/// other host on the segment, and naming the /24 would carve out all of them. The prefix on the
/// interface says how the machine routes; the /32 says where the machine IS, and that is the only
/// one of the two this measures.
///
/// **LOOPBACK IS LEFT OUT AND IT IS THE ONLY THING THIS STEP DECIDES.** It is every host's own and
/// identifies none of them, so a boundary that carved it out would carve out the caller's own
/// loopback too. That is true of every machine there is, which is why it is written here.
///
/// **WHICH OTHER INTERFACES ARE NOT THE MACHINE'S IS THE ROW'S TO SAY, in [ignoringInterfaces].** A
/// machine running workloads in containers carries interfaces something else made and renumbers on
/// its own schedule, and an address on one of those is not a place the machine can be reached — it
/// belongs to a network the row already knows by name, and it is rewritten whenever that network is
/// reconfigured, so writing it down would make a machine's stated addresses churn on facts that are
/// not about the machine. WHICH interfaces those are is a property of what the machine runs, and
/// this step runs on machines that run nothing of the sort. A tool that carried the names would be a
/// tool that knows what it is being used for.
///
/// **PUBLISHED AS A LIST ON ONE LINE, separated by a comma and a space.** A measurement crosses into
/// a row as one piece of text and the engine fills the slot with it whole, leaving the step it
/// reaches no room to re-separate it — so the separator has to be the one a list is written with, and
/// this is the last place that still holds the addresses as several things. A comma and a space is
/// how a list is written on one line in every file this ends up in, and a CIDR is a plain word to
/// each of them: digits, dots and a slash need no quoting anywhere.
///
/// **AN EMPTY READING IS NOT A READING.** A machine carries at least one address or nothing reached
/// it, so a measurement that found none is the question not having been put. Publishing an empty list
/// would let a boundary name nothing to keep out and report itself drawn.
final class MeasureHostAddresses extends ObservingStep {
  /// Measures the addresses this machine carries, passing over [ignoringInterfaces].
  const MeasureHostAddresses({this.ignoringInterfaces = const <String>[]});

  /// Builds the step from what the program gave it.
  factory MeasureHostAddresses.fromArguments(Arguments arguments) => MeasureHostAddresses(
    ignoringInterfaces: arguments.has('ignoring_interfaces')
        ? arguments.textList('ignoring_interfaces')
        : const <String>[],
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'ignoring_interfaces',
      kind: ArgumentKind.textList,
      describes:
          'the beginnings of the names of interfaces whose addresses are not places this machine '
          'can be reached — matched as PREFIXES, because the families that make them number and '
          'hash their own and a list of exact names lets the next one through. Leave it off on a '
          'machine that carries only its own interfaces',
      required: false,
    ),
  ];

  /// The beginnings of the names of interfaces whose addresses are not the machine's.
  final List<String> ignoringInterfaces;

  /// The name this machine's addresses are published under.
  static const MeasurementName published = MeasurementName('host_addresses');

  /// Whether [device] is one the row said is not the machine's.
  bool isIgnored(String device) => ignoringInterfaces.any(device.startsWith);

  /// The loopback range, which is every machine's own and identifies none.
  static const String loopbackRange = '127.0.0.0/8';

  /// The addresses [context]'s machine carries, each as a `/32`, in the order the kernel lists them.
  ///
  /// THROWS WHERE THE READING COULD NOT BE TAKEN, and that is the whole difference between this and
  /// a machine that genuinely carries nothing: `ip` writes nothing at exit zero for an interface with
  /// no address, so an empty answer at exit zero really is an empty interface, while a non-zero exit
  /// is no permission on the netlink socket or no `ip` on the machine. Folding the second into the
  /// first would publish "this machine has no addresses", which no machine that answered a command
  /// can be true of.
  Future<List<String>> measure(StepContext context) async {
    const List<String> argv = <String>['ip', '-4', '-o', 'addr', 'show', 'scope', 'global'];
    final CommandResult listed = await context.shell.run(
      const Command.observing(
        'ip',
        arguments: <String>['-4', '-o', 'addr', 'show', 'scope', 'global'],
      ),
    );
    if (!listed.ok) {
      throw CommandFailed(argv: argv, exitCode: listed.exitCode, stdout: '', stderr: listed.stderr);
    }

    final List<String> addresses = <String>[];
    for (final String line in listed.stdout.split('\n')) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      // `2: eth0    inet 157.90.201.153/32 scope global eth0` — the device is the second field and
      // the address the one after the `inet` marker. Read by position from the marker rather than by
      // a fixed index, because the fields in front of it differ between an interface with a label and
      // one without.
      if (fields.length < 2) {
        continue;
      }
      final int at = fields.indexOf('inet');
      if (at < 0 || at + 1 >= fields.length) {
        continue;
      }
      final String device = fields[1];
      if (isIgnored(device)) {
        continue;
      }
      final String address = fields[at + 1].split('/').first;
      if (!isCidr('$address/32') || cidrContains(loopbackRange, address)) {
        continue;
      }
      final String cidr = '$address/32';
      if (!addresses.contains(cidr)) {
        addresses.add(cidr);
      }
    }
    return addresses;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> addresses = await measure(context);
    if (addresses.isEmpty) {
      return const CheckResult.blocked(
        'this machine lists no address of its own outside the loopback range and the interfaces '
        'this row passes over, so nothing here says where it can be reached — and a boundary drawn '
        'around no address is no boundary',
      );
    }
    context.measurements.publish(published, addresses.join(', '));
    return CheckResult.satisfied(
      'this machine can be reached at ${addresses.join(', ')}, which is what a boundary drawn '
      'around it has to name',
    );
  }
}
