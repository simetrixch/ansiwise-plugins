import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Publishes the address this machine holds on the private network, for a row that writes it down.
///
/// **WHAT ASKS FOR THIS.** Whatever dials this machine over the private network is told where in a
/// file, and the address is the coordinator's to hand out: it exists from the join on, and a rejoin
/// hands out a fresh one. So nobody can answer it before the run that needs it — and one mistyped
/// octet points everything that dials it at a machine that is not this one.
///
/// **THE CLIENT IS ASKED THROUGH [tailnetAddress], the one reading this family shares.** A second
/// reading here could come to disagree with the steps that act on the address, and nothing would
/// report it.
///
/// **NO ADDRESS IS A REFUSAL, NEVER AN EMPTY VALUE.** A value written from nothing names no machine
/// while the row writing it reports success. Whether the program stops there is the row's
/// `on_failure` to say.
final class MeasureTailnetAddress extends ObservingStep {
  /// Measures the address this machine holds on the private network.
  const MeasureTailnetAddress();

  /// Builds the step from what the program gave it.
  factory MeasureTailnetAddress.fromArguments(Arguments arguments) => const MeasureTailnetAddress();

  /// What this step accepts: nothing, not even the elevation. [tailnetAddress] asks the client as
  /// root on every machine, because asked unelevated it answers a refusal that reads like "on no
  /// network".
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// The name this machine's address is published under.
  static const MeasurementName published = MeasurementName('tailnet_address');

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? address = await tailnetAddress(context);
    if (address == null) {
      // The state is read only to say WHICH absence this is: a client that answers without an
      // address has not joined, and one that does not answer at all says nothing either way.
      final String? state = await tailnetState(context);
      return CheckResult.blocked(
        state == null
            ? 'the private-network client on this machine could not be read, so nothing here says '
                  'which address it holds'
            : 'this machine holds no address on the private network (${tailnetStateLine(state)}) '
                  '— it has not joined one, and the join is what hands an address out',
      );
    }
    context.measurements.publish(published, address);
    return CheckResult.satisfied('this machine holds $address on the private network');
  }
}
