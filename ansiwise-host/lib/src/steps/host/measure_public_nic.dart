import 'package:ansiwise_core/ansiwise_core.dart';

/// Finds the interface a machine's public address arrives on, when that is not the one it answers by.
///
/// **The problem, on a machine with two interfaces.** One carries the public address — the ingress
/// ports and the connection an operator made land there — and the other carries the default route
/// that wins. A reply to something that arrived on the public address therefore leaves by the wrong
/// interface, and everything in between drops it as not belonging to the connection it is part of.
///
/// **Nothing about that is configured, and nothing here is written down.** Which interface, which
/// address and which gateway are read from the machine's own routes, so the same steps run on a
/// machine with one interface and on a machine with two, and do nothing on the first.
///
/// **The conditions for doing nothing.** A machine whose default-route interfaces carry no public
/// address at all has no problem to solve; so does one whose winning default route already leaves by
/// the public interface, which is every machine with a single interface; and so does one whose
/// public interface holds a default route with no gateway written on it, because there is then no
/// address to steer replies through. Each is a MEASUREMENT, and every step of the phase asks this
/// before doing anything — which is why a reading that could not be taken must never join them.
final class MeasurePublicNic extends ObservingStep {
  /// Measures the machine's public interface.
  const MeasurePublicNic();

  /// Builds the step from what the program gave it.
  factory MeasurePublicNic.fromArguments(Arguments arguments) => const MeasurePublicNic();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// The ranges that are not the public internet.
  ///
  /// The last two are the ones a shorter list forgets. An address out of the carrier-grade range is
  /// what a private overlay hands out, and an address out of the link-local range is what a machine
  /// gives itself when nothing gave it one — mistaking either for a public address picks the wrong
  /// interface and steers replies into a network that cannot answer them.
  static const List<String> privateRanges = <String>[
    '10.0.0.0/8',
    '172.16.0.0/12',
    '192.168.0.0/16',
    '100.64.0.0/10',
    '127.0.0.0/8',
    '169.254.0.0/16',
  ];

  /// Whether [address] is a real public address.
  static bool isPublicIpv4(String address) {
    if (!isCidr('$address/32')) {
      return false;
    }
    return !privateRanges.any((String range) => cidrContains(range, address));
  }

  /// What the machine's routes say about its public interface, or null when there is nothing to do.
  ///
  /// Shared with every step of this phase, so the machine is measured in one place and the seven
  /// files cannot come to disagree about which interface they are for.
  ///
  /// **NULL MEANS MEASURED AND NOTHING TO DO, and a reading that could not be taken THROWS.** Every
  /// step of this phase reads null as "this machine steers nothing" and answers satisfied on it, so
  /// a refused `ip` folded into null reported a machine that genuinely needs steering as one that
  /// does not — and did it in eight places at once, including the gate that is supposed to prove the
  /// drop-in folded in. The engine wraps every check in exactly one catch for this, at
  /// `ansiwise-core/lib/src/engine/step_execution.dart`, and turns what is thrown into a refusal
  /// naming the tool's own words; throwing is therefore how a measurement says it was not taken,
  /// and it needs no branch in any of the eight.
  static Future<PublicNic?> measure(StepContext context) async {
    final List<_DefaultRoute> routes = await _defaultRoutes(context);
    if (routes.isEmpty) {
      return null;
    }

    for (final _DefaultRoute route in routes) {
      final String? address = await _publicAddressOf(context, route.device);
      if (address == null) {
        continue;
      }
      if (route.gateway.isEmpty) {
        return null;
      }
      // The winning route is the one with the lowest metric, and if that is already this interface
      // then replies leave the right way by themselves.
      final _DefaultRoute winner = routes.reduce(
        (_DefaultRoute a, _DefaultRoute b) => a.metric <= b.metric ? a : b,
      );
      if (winner.device == route.device) {
        return null;
      }
      return PublicNic(
        device: route.device,
        address: address,
        gateway: route.gateway,
        mac: await _macOf(context, route.device),
      );
    }
    return null;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await measure(context);
    if (nic == null) {
      return const CheckResult.satisfied(
        'the default route already leaves by the interface carrying the public address, or there is '
        'no public address on a default-route interface — either way nothing has to be steered',
      );
    }
    return CheckResult.satisfied(
      '${nic.address} arrives on ${nic.device} (${nic.mac}) while the default route leaves by '
      'another interface, so replies have to be steered out ${nic.gateway}',
    );
  }

  /// The machine's default routes, in the order it lists them.
  ///
  /// AN EMPTY LIST IS AN ANSWER AND A NON-ZERO EXIT IS NOT. `ip route show` writes nothing and exits
  /// zero on a machine that carries no default route, so an empty answer really is a machine with
  /// none. A non-zero exit is the question not having been put — no permission on the netlink
  /// socket, no `ip` on the machine — and folded into the same empty list it read as a machine with
  /// no default route, which every step of this phase then answers "nothing has to be steered" over.
  static Future<List<_DefaultRoute>> _defaultRoutes(StepContext context) async {
    final CommandResult routes = await context.shell.run(
      const Command.observing('ip', arguments: <String>['-4', 'route', 'show', 'default']),
    );
    if (!routes.ok) {
      throw CommandFailed(
        argv: _showDefaultRoutes,
        exitCode: routes.exitCode,
        stdout: '',
        stderr: routes.stderr,
      );
    }
    return <_DefaultRoute>[
      for (final String line in routes.stdout.split('\n'))
        if (_DefaultRoute.read(line) case final _DefaultRoute route) route,
    ];
  }

  /// What the machine's default routes are read with.
  static const List<String> _showDefaultRoutes = <String>['ip', '-4', 'route', 'show', 'default'];

  /// The first public address on [device], or null when it carries none.
  ///
  /// The same rule as the routes above: an interface carrying no address answers with nothing at
  /// exit zero, so a non-zero exit is the reading not having been taken and never an interface with
  /// no public address on it.
  static Future<String?> _publicAddressOf(StepContext context, String device) async {
    final List<String> argv = <String>['ip', '-4', '-o', 'addr', 'show', 'dev', device];
    final CommandResult addresses = await context.shell.run(
      Command.observing(argv.first, arguments: argv.sublist(1)),
    );
    if (!addresses.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: addresses.exitCode,
        stdout: '',
        stderr: addresses.stderr,
      );
    }
    for (final String line in addresses.stdout.split('\n')) {
      final List<String> fields = line.trim().split(RegExp(r'\s+'));
      final int at = fields.indexOf('inet');
      if (at < 0 || at + 1 >= fields.length) {
        continue;
      }
      final String address = fields[at + 1].split('/').first;
      if (isPublicIpv4(address)) {
        return address;
      }
    }
    return null;
  }

  /// The hardware address of [device], read from the kernel's own listing of it.
  ///
  /// Without it the drop-in cannot be keyed the way the installer's own file is keyed, so it would
  /// become a second declaration of the interface rather than folding into the one that is there.
  /// That is why an unreadable one stops the whole phase rather than being worked around: saying so
  /// and then returning null hands back the value that means nothing has to be steered.
  ///
  /// [device] is the name the routes above answered with, so the kernel has it. A file that is not
  /// there, or one that is there and empty, is therefore a reading that was not taken.
  static Future<String> _macOf(StepContext context, String device) async {
    final String path = '/sys/class/net/$device/address';
    if (!await context.files.exists(path)) {
      throw StateError(
        '$path is not there, and it is where the kernel states the hardware address of $device — '
        'which the routes of this machine just named, so the interface is one it has',
      );
    }
    final String mac = (await context.files.read(path)).trim();
    if (mac.isEmpty) {
      throw StateError(
        '$path is empty, and the drop-in that steers replies out $device is keyed on the hardware '
        "address it states — a drop-in keyed on nothing becomes a second declaration of the "
        "interface instead of folding into the installer's",
      );
    }
    return mac;
  }
}

/// What the machine's routes say about the interface its public address arrives on.
final class PublicNic {
  /// Describes one machine's public interface.
  const PublicNic({
    required this.device,
    required this.address,
    required this.gateway,
    required this.mac,
  });

  /// The interface the public address is on.
  final String device;

  /// The public address itself.
  final String address;

  /// The gateway that interface reaches the internet through.
  final String gateway;

  /// The interface's hardware address, which is what the drop-in is keyed on.
  final String mac;
}

/// One default route, as the machine lists it.
final class _DefaultRoute {
  const _DefaultRoute({required this.device, required this.gateway, required this.metric});

  /// The route [line] describes, or null when it describes none.
  ///
  /// A route with no metric written out is the kernel's zero, which wins against every route that
  /// says a number — so an absent metric is read as zero rather than as unknown.
  static _DefaultRoute? read(String line) {
    final List<String> fields = line.trim().split(RegExp(r'\s+'));
    if (fields.isEmpty || fields.first != 'default') {
      return null;
    }
    final String device = _after(fields, 'dev');
    if (device.isEmpty) {
      return null;
    }
    return _DefaultRoute(
      device: device,
      gateway: _after(fields, 'via'),
      metric: int.tryParse(_after(fields, 'metric')) ?? 0,
    );
  }

  static String _after(List<String> fields, String key) {
    final int at = fields.indexOf(key);
    return at < 0 || at + 1 >= fields.length ? '' : fields[at + 1];
  }

  final String device;
  final String gateway;
  final int metric;
}
