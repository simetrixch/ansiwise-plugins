import 'package:ansiwise_api/ansiwise_api.dart';

/// Finds the name servers this machine really reaches the internet through.
///
/// **The order of the two sources is the incident.** On a machine running the system resolver — the
/// pinned Ubuntu's default — the resolver file names `127.0.0.53`, which is the local stub. Reading
/// that file first produces an answer immediately, and the answer is one no pod can reach: a pod's
/// own loopback is not the machine's. So the resolver is asked first for the servers it actually
/// forwards to, and the file is only read when that yields nothing.
///
/// **Loopback goes from BOTH sources, not only from the first.** A machine can name a local stub in
/// either place, and dropping it from one of them leaves the other able to produce it.
///
/// **A zone id makes an address unusable as a forwarder.** A link-local address is written with the
/// interface it is valid on after a `%`, and everything from that character on is cut.
///
/// **A public resolver is the wrong thing to fall back on.** On a machine behind address
/// translation, outbound name lookups to a public resolver are simply blocked, and only the
/// machine's own provider answers — while on an ordinary machine that same provider answers too. So
/// the machine's own is the robust choice, and an explicitly configured list beats both.
final class DetectHostUpstreamResolvers extends ObservingStep {
  /// Measures the machine's real name servers, reading [resolvConf] only as the second source.
  const DetectHostUpstreamResolvers({required this.resolvConf});

  /// Builds the step from what the program gave it.
  factory DetectHostUpstreamResolvers.fromArguments(Arguments arguments) =>
      DetectHostUpstreamResolvers(resolvConf: arguments.text('resolv_conf'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'resolv_conf',
      kind: ArgumentKind.text,
      describes: "the machine's resolver file, read only when the system resolver names nothing",
      required: false,
      defaultValue: defaultResolvConf,
    ),
  ];

  /// The file the second source reads.
  static const String defaultResolvConf = '/etc/resolv.conf';

  /// The text a program file writes where this machine's own name servers belong.
  ///
  /// A program file ships inside the binary to every installation and nothing rewrites it, so the
  /// addresses of ONE machine cannot stand in it. What stands there instead is this marked slot,
  /// and the step that writes the text fills it from what the machine says — the same shape every
  /// other value one installation owns is written in.
  ///
  /// **A slot is not a template.** No expression, no condition and no loop, only a name standing for
  /// one value this run holds.
  static const String placeholder = '<upstream-servers>';

  /// [text] with [placeholder] replaced by this machine's name servers, or null when it names none.
  ///
  /// The addresses stand where the slot was, one after another separated by a space, which is how
  /// every configuration this platform writes a list of name servers into reads them.
  ///
  /// Text carrying no slot comes back as it is, without the machine being measured at all — so a
  /// caller may hand any text in and does not have to know whether it names one.
  static Future<String?> filled(StepContext context, String text) async {
    if (!text.contains(placeholder)) {
      return text;
    }
    final List<String> found = await detect(context);
    if (found.isEmpty) {
      return null;
    }
    return text.replaceAll(placeholder, found.join(' '));
  }

  /// The name servers this machine reaches the internet through, in the order they were found.
  ///
  /// Shared with the step that writes them into the cluster's own resolver, so the machine is
  /// measured in one place and the two cannot come to disagree about what it said.
  static Future<List<String>> detect(
    StepContext context, {
    String resolvConf = defaultResolvConf,
  }) async {
    final List<String> fromResolver = _usable(await _fromSystemResolver(context));
    if (fromResolver.isNotEmpty) {
      return fromResolver;
    }
    return _usable(await _fromResolvConf(context, resolvConf));
  }

  /// The file the second source reads.
  final String resolvConf;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> found = await detect(context, resolvConf: resolvConf);
    if (found.isEmpty) {
      return CheckResult.blocked(
        'this machine names no name server a pod could reach — the system resolver reported none and '
        '$resolvConf named none that is not a local stub, so lookups from inside the cluster have '
        'nowhere to go',
      );
    }
    return CheckResult.satisfied('this machine reaches the internet through ${found.join(', ')}');
  }

  /// What the system resolver says it forwards to.
  static Future<List<String>> _fromSystemResolver(StepContext context) async {
    final CommandResult status = await context.shell.run(
      const Command.observing('resolvectl', <String>['status']),
    );
    if (!status.ok) {
      return const <String>[];
    }
    final List<String> found = <String>[];
    for (final String line in status.stdout.split('\n')) {
      for (final String label in _labels) {
        final int at = line.indexOf(label);
        if (at < 0) {
          continue;
        }
        found.addAll(
          line
              .substring(at + label.length)
              .split(RegExp(r'\s+'))
              .where((String value) => value.isNotEmpty),
        );
        break;
      }
    }
    return found;
  }

  /// What the resolver file names.
  static Future<List<String>> _fromResolvConf(StepContext context, String path) async {
    if (!await context.files.exists(path)) {
      return const <String>[];
    }
    final List<String> found = <String>[];
    for (final String line in (await context.files.read(path)).split('\n')) {
      final String trimmed = line.trim();
      if (!trimmed.startsWith('nameserver')) {
        continue;
      }
      found.addAll(
        trimmed
            .substring('nameserver'.length)
            .split(RegExp(r'\s+'))
            .where((String value) => value.isNotEmpty),
      );
    }
    return found;
  }

  /// [found] with the zone ids cut, the local stubs dropped and the repeats removed.
  static List<String> _usable(List<String> found) {
    final List<String> usable = <String>[];
    for (final String address in found) {
      final String withoutZone = address.split('%').first.trim();
      if (withoutZone.isEmpty || _isLoopback(withoutZone) || usable.contains(withoutZone)) {
        continue;
      }
      usable.add(withoutZone);
    }
    return usable;
  }

  /// Whether [address] is the machine's own loopback, which a pod cannot reach.
  static bool _isLoopback(String address) =>
      address.startsWith('127.') || address == '::1' || address == '0:0:0:0:0:0:0:1';

  /// The two labels the system resolver writes its forwarders behind.
  ///
  /// The list of them and the one currently in use, in that order — a line matches one label and the
  /// search for the other stops there, so the list is never read twice out of the same line.
  static const List<String> _labels = <String>['DNS Servers:', 'Current DNS Server:'];
}
