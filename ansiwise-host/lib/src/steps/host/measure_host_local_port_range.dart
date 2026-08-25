import 'package:ansiwise_core/ansiwise_core.dart';

/// Measures the source ports this machine opens its own outgoing connections from.
///
/// **What this is for, and it is not about this machine at all.** Whatever masquerades another
/// address range behind this machine's own address picks a source port for every connection it
/// rewrites, and it is free to pick one outside the range the machine itself uses. Where the network
/// this machine hangs on only carries the answer back for the ports the machine is known to open,
/// every connection given one of the others is simply never answered. Nothing on the machine reports
/// that: no rule dropped it, no log line names it, and what is seen is a connection sitting at its
/// timeout. Measured on one machine at a hosting provider: from a masqueraded address, half of the
/// outgoing connections were answered and half were not, and the boundary between the two sets of
/// source ports was exactly the low end of this range.
///
/// **So the range is read from the machine rather than written down anywhere.** What works for the
/// machine's own connections is what the masquerading component is held to, and that is a rule about
/// any network rather than about one provider's — a machine whose kernel is tuned to another range
/// hands that other range on, and a network that carries every port back is described correctly too.
///
/// **The kernel is asked, through the interface the kernel itself defines.** [path] is where Linux
/// publishes the setting spelled `net.ipv4.ip_local_port_range`, and it is the same file the
/// machine's own tooling reads and writes. It is not a distribution's choice of where to put
/// something, so this step takes no path from a row and no account from one either: the file is
/// readable to everybody. Asking a command for it afterwards would be reading this same file through
/// a second tool, which is one source answered twice rather than a second source.
///
/// **Two numbers or nothing.** The file holds the low and the high port with whitespace between
/// them, and null is the absence of a reading rather than a value: a caller told "1 65535" when
/// nothing could be read would masquerade into a range nobody measured and report it as an
/// alignment.
final class MeasureHostLocalPortRange extends ObservingStep {
  /// Measures the range by reading [path].
  const MeasureHostLocalPortRange();

  /// Builds the step from what the program gave it.
  factory MeasureHostLocalPortRange.fromArguments(Arguments arguments) =>
      const MeasureHostLocalPortRange();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// Where the kernel publishes `net.ipv4.ip_local_port_range`.
  static const String path = '/proc/sys/net/ipv4/ip_local_port_range';

  /// The two ports this machine opens its own connections between, low one first, or null.
  ///
  /// **This is the ONE reading of this machine's range, and whatever is held to it takes it from
  /// here.** The component that masquerades another address range behind this machine's address is
  /// configured from another package, and that package and this one do not depend on each other;
  /// what carries the value across the line is the measurement this step publishes and the row below
  /// it reads. A second reading over there would be a second answer to one question, and two answers
  /// can come to disagree with nothing to report it.
  ///
  /// Written back with ONE space, whatever the file separated the two numbers with, so what is
  /// published is one spelling and a reader of the record is not left wondering whether a tab means
  /// something.
  static Future<String?> measure(StepContext context) async {
    if (!await context.files.exists(path)) {
      return null;
    }
    final String written = (await context.files.read(path)).trim();
    final List<String> numbers = written
        .split(RegExp(r'\s+'))
        .where((String each) => each.isNotEmpty)
        .toList();
    if (numbers.length != 2) {
      return null;
    }
    final int? low = int.tryParse(numbers.first);
    final int? high = int.tryParse(numbers.last);
    if (low == null || high == null) {
      return null;
    }
    if (low < _lowestPort || high > _highestPort || low > high) {
      return null;
    }
    return '$low $high';
  }

  /// The lowest port number that exists, so a reading below it names no port.
  static const int _lowestPort = 1;

  /// The highest port number that exists, so a reading above it names no port.
  static const int _highestPort = 65535;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? range = await measure(context);
    if (range == null) {
      // A measurement that could not be taken is not a measurement, and this step exists to take
      // one. Answering satisfied here would put a range nothing read into the record, and the engine
      // stamps a satisfied observing row PROVEN.
      return const CheckResult.blocked(
        '$path names no pair of port numbers, so nothing here says which ports this machine opens '
        'its own connections from',
      );
    }
    context.measurements.publish(const MeasurementName('local_port_range'), range);
    return CheckResult.satisfied(
      '$path says this machine opens its own connections from ports $range',
    );
  }
}
