import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

/// Switches the steering service on, and puts the kernel state back whenever it is not there.
///
/// **A service that is enabled and active is not a machine that is steering.** The two things the
/// service installs live only in the kernel, and anything that empties the machine's rule set takes
/// them away while the service goes on reporting itself as having succeeded. So the state itself is
/// what this reads, and finding it gone is what starts the service again.
final class ActivatePublicSrcRouting extends ReversibleStep<bool> {
  /// Switches [unitName] on, expecting the rule keyed on [mark] into table [table].
  const ActivatePublicSrcRouting({required this.unitName, required this.mark, required this.table});

  /// Builds the step from what the program gave it.
  factory ActivatePublicSrcRouting.fromArguments(Arguments arguments) => ActivatePublicSrcRouting(
    unitName: arguments.text('unit_name'),
    mark: arguments.text('mark'),
    table: arguments.integer('table'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No defaults at all. The service's name is the installation's, and the mark and the table are
    // what the steps that wrote them chose against THIS machine — a default here would let this
    // step go on looking for a rule the machine never carried and report the steering as installed.
    ArgumentSpec(
      name: 'unit_name',
      kind: ArgumentKind.text,
      describes: 'the service that installs the steering',
    ),
    ArgumentSpec(
      name: 'mark',
      kind: ArgumentKind.text,
      describes:
          'the mark the installed rule is keyed on, as the rules the service loads put it on',
    ),
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes:
          'the routing table the marked replies are steered into, as the drop-in that holds the '
          'public gateway numbers it',
    ),
  ];

  /// The service that installs the steering.
  final String unitName;

  /// The mark the rule is keyed on.
  final String mark;

  /// The table the marked replies go into.
  final int table;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await DetectPublicNic.detect(context) == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so there is no service to switch on',
      );
    }

    final List<String> missing = <String>[
      if (!await _answers(context, 'is-enabled', 'enabled'))
        'it does not come back after a restart',
      if (!await _answers(context, 'is-active', 'active')) 'it is not active',
      if (!await _ruleInstalled(context)) 'the rule keyed on $mark is not in the kernel',
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied('$unitName is on and the kernel carries what it installs');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['systemctl', 'enable', '--now', unitName]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>['systemctl', 'enable', unitName]);
    // Restarted rather than started: a service that reports itself as having succeeded is not
    // started again, and running it once more is what puts the kernel state back.
    await _mustRun(context, <String>['systemctl', 'restart', unitName]);
  }

  /// Whether the service already comes back after a restart, read before it is switched on.
  ///
  /// A machine can arrive with the service enabled and the kernel state gone, and this step is then
  /// only the restart that puts the state back. Switching such a service off would take away
  /// steering this run never installed.
  @override
  Future<bool> capture(StepContext context) => _answers(context, 'is-enabled', 'enabled');

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    // This is what takes the kernel state away — the service's own stopping commands remove the
    // marking rules and the rule keyed on the mark.
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
      Command.observing('systemctl', <String>[question, unitName]),
    );
    return answer.trimmed == wanted;
  }

  Future<bool> _ruleInstalled(StepContext context) async {
    final CommandResult rules = await context.shell.run(
      const Command.observing('ip', <String>['-4', 'rule', 'show']),
    );
    if (!rules.ok) {
      return false;
    }
    return rules.stdout
        .split('\n')
        .any((String line) => line.contains('$mark/$mark') && line.contains('lookup $table'));
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
