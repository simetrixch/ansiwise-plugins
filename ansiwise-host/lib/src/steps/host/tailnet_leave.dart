import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Takes this machine off the private network, and keeps everything it needs to come back.
///
/// **Leaving is not logging out, and the difference is the whole reason this step exists beside
/// the logout step.** `tailscale down` disconnects: the client keeps its node key and its
/// coordinator, the coordinator keeps its node, and nothing is revoked anywhere — so the machine
/// can re-establish its membership later with what it already holds. `tailscale logout` discards
/// the node key, after which only a fresh credential can bring the machine back.
///
/// **The effect is asserted, never the exit code.** The client's own backend state is read again
/// after the command, because a `down` that returns zero while the client still reports Running is
/// a machine everything keeps dialling on an address the operator believes is gone.
final class TailnetLeave extends ReversibleStep<bool> {
  /// Takes the client off its network.
  const TailnetLeave();

  /// Builds the step from what the program gave it.
  factory TailnetLeave.fromArguments(Arguments arguments) => const TailnetLeave();

  /// What this step accepts: nothing. Which network the machine leaves is not a choice — a client
  /// is a member of at most one — and everything else is the tool's own.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? state = await tailnetState(context);
    if (state == null) {
      return const CheckResult.blocked(
        'the client\'s own state cannot be read, and a machine taken off a network nobody could '
        'read is a machine nobody can describe afterwards — is the client installed and its '
        'daemon running?',
      );
    }
    return state == tailnetRunning
        ? const CheckResult.ready()
        : CheckResult.satisfied('already off the network (${tailnetStateLine(state)})');
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.argv(<String>[tailnetTool, 'down']);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult down = await context.shell.run(
      const Command.detailed(tailnetTool, arguments: <String>['down'], elevated: true),
    );
    if (down.exitCode != 0) {
      throw CommandFailed(
        argv: const <String>[tailnetTool, 'down'],
        exitCode: down.exitCode,
        stdout: down.stdout,
        stderr: down.stderr,
      );
    }
  }

  /// Whether the machine was ON the network before this ran — which is the only state the undo has
  /// to put back. A machine that was already off had nothing taken away.
  @override
  Future<bool> capture(StepContext context) async => await tailnetState(context) == tailnetRunning;

  /// Puts the membership back with a BARE `up` — the client's own special case for "bring the
  /// network up and change nothing". The moment any flag is present the client re-derives its whole
  /// preference set from the command line and refuses, because the machine was joined with
  /// non-default flags; bare, it comes back up on the preferences it holds.
  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      return;
    }
    await context.shell.run(
      const Command.detailed(
        tailnetTool,
        arguments: <String>['up'],
        elevated: true,
        // Bounded, because a client whose credential died while it was down prints a login
        // address and waits for a person this unwind does not have.
        timeout: Duration(seconds: 60),
      ),
    );
  }
}
