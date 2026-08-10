import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_public_nic.dart';

/// Puts the written network configuration into the running kernel.
///
/// **What is checked is the kernel, not the file.** A configuration that was written and never
/// applied and one that was applied both leave the same file on disk. The two things this program
/// puts into the kernel — the rule that sends traffic from the public address to its own table, and
/// the route in that table — are readable, and they are what says whether this still has work to do.
/// A machine that was restarted with the file in place comes back with both, and this correctly does
/// nothing.
final class ApplyNetplan extends IrreversibleStep {
  /// Applies the configuration, expecting the rule into table [table] for the public address.
  const ApplyNetplan({required this.table});

  /// Builds the step from what the program gave it.
  factory ApplyNetplan.fromArguments(Arguments arguments) =>
      ApplyNetplan(table: arguments.integer('table'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default: this is what the drop-in the program wrote numbered the table, and a default here
    // would have this step read a table nothing fills and report the configuration as applied.
    ArgumentSpec(
      name: 'table',
      kind: ArgumentKind.integer,
      describes:
          'the routing table whose only route is the public gateway, as the drop-in that holds it '
          'numbers it',
    ),
  ];

  /// The table holding the public gateway.
  final int table;

  @override
  String get irreversibleReason =>
      'the rules and the route are in the kernel from now on, and deleting the file does not take '
      'them out again — only applying the configuration once more or restarting the machine does, '
      'and either of those drops a session that arrived on the public address, which is how an '
      'operator is connected while this runs';

  @override
  Future<CheckResult> check(StepContext context) async {
    final PublicNic? nic = await DetectPublicNic.detect(context);
    if (nic == null) {
      return const CheckResult.satisfied(
        'nothing is steered on this machine, so there is nothing to apply',
      );
    }

    final List<String> missing = <String>[
      if (!await _hasRule(context, nic)) 'the rule sending ${nic.address} into table $table',
      if (!await _hasRoute(context, nic)) 'the route through ${nic.gateway} in table $table',
    ];
    if (missing.isEmpty) {
      return CheckResult.satisfied('the kernel carries the rule and the route for ${nic.address}');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    context.log.warn(
      'applying the network configuration — a session that arrived on the public address is on the '
      'path this is about to change',
    );
    final CommandResult applied = await context.shell.run(Command(_argv.first, _argv.sublist(1)));
    if (!applied.ok) {
      throw CommandFailed(argv: _argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  Future<bool> _hasRule(StepContext context, PublicNic nic) async {
    final CommandResult rules = await context.shell.run(
      const Command.observing('ip', <String>['-4', 'rule', 'show']),
    );
    if (!rules.ok) {
      return false;
    }
    return rules.stdout
        .split('\n')
        .any((String line) => line.contains(nic.address) && line.contains('lookup $table'));
  }

  Future<bool> _hasRoute(StepContext context, PublicNic nic) async {
    final CommandResult routes = await context.shell.run(
      Command.observing('ip', <String>['-4', 'route', 'show', 'table', '$table']),
    );
    return routes.ok && routes.stdout.contains(nic.gateway);
  }

  static const List<String> _argv = <String>['netplan', 'apply'];
}
