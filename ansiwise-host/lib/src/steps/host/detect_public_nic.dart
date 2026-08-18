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
/// **The two conditions for doing nothing.** A machine whose default-route interfaces carry no
/// public address at all has no problem to solve. So does one whose winning default route already
/// leaves by the public interface, which is every machine with a single interface. Either way this
/// answers that there is nothing to do, and every step of the phase asks it before doing anything.
final class DetectPublicNic extends ObservingStep {
  /// Measures the machine's public interface.
  const DetectPublicNic();

  /// Builds the step from what the program gave it.
  factory DetectPublicNic.fromArguments(Arguments arguments) => const DetectPublicNic();

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
  static Future<PublicNic?> detect(StepContext context) async {
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
      final String? mac = await _macOf(context, route.device);
      if (mac == null) {
        return null;
      }
      return PublicNic(device: route.device, address: address, gateway: route.gateway, mac: mac);
    }
    return null;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await detect(context);
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
  static Future<List<_DefaultRoute>> _defaultRoutes(StepContext context) async {
    final CommandResult routes = await context.shell.run(
      const Command.observing('ip', arguments: <String>['-4', 'route', 'show', 'default']),
    );
    if (!routes.ok) {
      return const <_DefaultRoute>[];
    }
    return <_DefaultRoute>[
      for (final String line in routes.stdout.split('\n'))
        if (_DefaultRoute.read(line) case final _DefaultRoute route) route,
    ];
  }

  /// The first public address on [device], or null when it carries none.
  static Future<String?> _publicAddressOf(StepContext context, String device) async {
    final CommandResult addresses = await context.shell.run(
      Command.observing('ip', arguments: <String>['-4', '-o', 'addr', 'show', 'dev', device]),
    );
    if (!addresses.ok) {
      return null;
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

  /// The hardware address of [device], or null when it cannot be read.
  ///
  /// Without it the drop-in cannot be keyed the way the installer's own file is keyed, so it would
  /// become a second declaration of the interface rather than folding into the one that is there.
  /// That is why an unreadable one stops the whole phase rather than being worked around.
  static Future<String?> _macOf(StepContext context, String device) async {
    final String path = '/sys/class/net/$device/address';
    if (!await context.files.exists(path)) {
      return null;
    }
    final String mac = (await context.files.read(path)).trim();
    return mac.isEmpty ? null : mac;
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
