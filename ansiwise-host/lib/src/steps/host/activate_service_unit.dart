import 'package:ansiwise_core/ansiwise_core.dart';

/// Switches one service on, and makes it come back after a restart of the machine.
///
/// **Two questions, and both have to hold.** `is-enabled` says the service comes back when the
/// machine does, `is-active` says it is running now, and either can be true without the other: a
/// machine can arrive with the unit enabled and the service crashed, or with somebody's hand-started
/// service that would not survive a restart. Only both together are the state this step is for, so
/// anything less is work to do rather than a partial pass.
///
/// **The apply restarts rather than starts.** A service that is enabled and FAILED is not started
/// again by `start` on every init system alike, and a service whose unit file was rewritten by an
/// earlier row of the same program is still running the old text until something restarts it. A
/// restart covers both, and for a stopped service it is simply the start.
///
/// **What its check never reads is the service's own health.** Active is the service manager's word;
/// whether what is running behaves is the business of a wait or a gate a program places after this
/// row, because how to ask a service whether it works is a fact of that service.
final class ActivateServiceUnit extends ReversibleStep<bool> {
  /// Switches [unitName] on.
  const ActivateServiceUnit({required this.unitName});

  /// Builds the step from what the program gave it.
  factory ActivateServiceUnit.fromArguments(Arguments arguments) =>
      ActivateServiceUnit(unitName: arguments.text('unit_name'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default. The unit's name is the installation's own — it is the base name of the file
    // another row wrote — and a default here would switch on a service nobody installed.
    ArgumentSpec(
      name: 'unit_name',
      kind: ArgumentKind.text,
      describes: 'the service to switch on, as the unit file another row of the program names it',
    ),
  ];

  /// The service to switch on.
  final String unitName;

  @override
  Future<CheckResult> check(StepContext context) async {
    final bool enabled = await _answers(context, 'is-enabled', 'enabled');
    final bool active = await _answers(context, 'is-active', 'active');
    if (enabled && active) {
      return CheckResult.satisfied('$unitName is active and comes back after a restart');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['systemctl', 'enable', '--now', unitName]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>['systemctl', 'enable', unitName]);
    // Restarted rather than started: a running service whose unit file or binary an earlier row
    // replaced is still the old one until something restarts it, and for a stopped or failed
    // service the restart is simply the start.
    await _mustRun(context, <String>['systemctl', 'restart', unitName]);
  }

  /// Whether the service already comes back after a restart, read before it is switched on.
  ///
  /// A machine can arrive with the service enabled and merely crashed, and this step is then only
  /// the restart. Switching such a service off in an undo would take away something this run never
  /// installed.
  @override
  Future<bool> capture(StepContext context) => _answers(context, 'is-enabled', 'enabled');

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command.detailed(
        'systemctl',
        arguments: <String>['disable', '--now', unitName],
        elevated: true,
      ),
    );
  }

  Future<bool> _answers(StepContext context, String question, String wanted) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('systemctl', arguments: <String>[question, unitName]),
    );
    return answer.trimmed == wanted;
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}
