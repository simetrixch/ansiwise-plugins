import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Logs this machine's client out, discarding the node key that made it a member.
///
/// **What the logout is FOR: making the next join real.** The client keeps serving a cached view
/// of the network for a while after its node is deleted at the coordinator, so a machine that
/// still reports Running is skipped by a join as "already on the network" — and a re-join that was
/// skipped repaired nothing. Discarding the node key is what turns the next join from a no-op into
/// a registration.
///
/// **The exit code is tolerated and the EFFECT asserted.** A machine that was already logged out
/// answers either way; what may never happen is the client still holding its key afterwards while
/// this step reports done, because everything after this step is built on that key being gone.
final class TailnetLogout extends IrreversibleStep {
  /// Discards the client's credential.
  const TailnetLogout();

  /// Builds the step from what the program gave it.
  factory TailnetLogout.fromArguments(Arguments arguments) => const TailnetLogout();

  /// What this step accepts: nothing. There is only one credential a client holds, and discarding
  /// it is the whole of the act.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  @override
  String get irreversibleReason =>
      'logging out discards the node key — the credential that made this machine a member — and '
      'nothing on this machine can mint another; only a fresh join credential from the '
      'coordinator brings it back';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? state = await tailnetState(context);
    if (state == null) {
      return const CheckResult.blocked(
        'the client\'s own state cannot be read, so whether it still holds a credential cannot '
        'be known — is the client installed and its daemon running?',
      );
    }
    // Only the state that PROVES the key is gone counts as done. A client that is merely down
    // still holds its key, and logging out from there is real work: it is exactly the state a
    // disconnect leaves behind.
    return state == tailnetNeedsLogin
        ? CheckResult.satisfied('already logged out (${tailnetStateLine(state)})')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.argv(<String>[tailnetTool, 'logout']);

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(
      const Command.detailed(
        tailnetTool,
        arguments: <String>['logout'],
        elevated: true,
        // Bounded: a client that cannot reach its coordinator to say goodbye may wait, and the
        // key is discarded locally either way — which the check after this is what proves.
        timeout: Duration(seconds: 60),
      ),
    );
  }
}
