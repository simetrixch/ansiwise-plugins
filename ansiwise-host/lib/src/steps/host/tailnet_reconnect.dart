import 'package:ansiwise_core/ansiwise_core.dart';

import 'tailnet_client.dart';

/// Re-establishes this machine's membership with the credential the client already holds.
///
/// **A BARE `up`, with not one flag on it.** That is the client's own special case for "bring the
/// network up and change nothing"; the moment ANY flag is present it re-derives the whole
/// preference set from the command line and refuses with "changing settings via 'tailscale up'
/// requires mentioning all non-default flags" — and a machine joined with a login server and DNS
/// declined holds two non-default preferences, so a flag as innocent as a timeout would make this
/// fail on every machine ever joined. The wait is bounded from OUTSIDE instead, because it has to
/// be: a client whose node key is gone prints a login address and waits for a person this run does
/// not have. The bound is what cuts that wait short; an `up` that reaches its coordinator settles
/// in seconds.
///
/// **This is the verb for a machine that was disconnected, or whose daemon stopped.** A machine
/// whose credential is GONE cannot come back this way — its client ends the wait still holding
/// nothing — and the check after the apply is what turns that into a failure that says so, rather
/// than a success that leaves the machine off the network with everybody told otherwise.
final class TailnetReconnect extends ReversibleStep<bool> {
  /// Brings the membership back up.
  const TailnetReconnect({required this.waitSeconds});

  /// Builds the step from what the program gave it.
  factory TailnetReconnect.fromArguments(Arguments arguments) =>
      TailnetReconnect(waitSeconds: arguments.integer('wait_seconds'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'wait_seconds',
      kind: ArgumentKind.integer,
      required: false,
      defaultValue: 60,
      describes:
          'how long the bare up may take before it is cut short — the only thing this bound ever '
          'cuts is the wait for a person, which a client with no usable credential falls into',
    ),
  ];

  /// How long the bare `up` may take.
  final int waitSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? state = await tailnetState(context);
    if (state == null) {
      return const CheckResult.blocked(
        'the client\'s own state cannot be read, so whether this machine is on a network cannot '
        'be known — is the client installed and its daemon running?',
      );
    }
    return state == tailnetRunning
        ? const CheckResult.satisfied('already on the network — nothing to re-establish')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.argv(<String>[tailnetTool, 'up']);

  @override
  Future<void> apply(StepContext context) async {
    // The exit code is tolerated and the EFFECT asserted by the check that runs after this: a
    // client cut short by the bound exits non-zero whether or not the membership came up, so the
    // backend state is the only honest verdict either way.
    await context.shell.run(
      Command.detailed(
        tailnetTool,
        arguments: const <String>['up'],
        elevated: true,
        timeout: Duration(seconds: waitSeconds),
      ),
    );
    final String? state = await tailnetState(context);
    if (state != tailnetRunning) {
      throw StateError(
        'the client came back as "${state ?? 'unreadable'}", not $tailnetRunning — it holds no '
        'usable credential, and only a fresh one minted at the coordinator can bring this '
        'machine back',
      );
    }
  }

  /// Whether the machine was already ON the network before this ran. The undo takes back only a
  /// membership THIS step established.
  @override
  Future<bool> capture(StepContext context) async => await tailnetState(context) == tailnetRunning;

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      const Command.detailed(tailnetTool, arguments: <String>['down'], elevated: true),
    );
  }
}
