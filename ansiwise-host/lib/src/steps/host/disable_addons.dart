import 'package:ansiwise_api/ansiwise_api.dart';

import 'addon_status.dart';

/// Switches off the addons a program names, whatever the snap switched on by itself.
///
/// **Without this pass a cluster's state depends on what the snap happened to do.** Some addons come
/// on by themselves when the snap installs. Naming an addon here means a machine ends up in the same
/// state whatever the snap default was and whatever a previous run did.
///
/// **An empty list is a step with nothing to do, not an error.** A row that names no addon is a row
/// that wants none switched off — and it says so, rather than leaving the question unanswered.
///
/// Switching off an addon that is already off is accepted by the snap, so nothing here has to guard
/// against two runs racing each other.
final class DisableAddons extends ReversibleStep<List<String>> {
  /// Switches off each of [addons] that is on.
  const DisableAddons({
    required this.addons,
    required this.statusCommand,
    required this.enableCommand,
    required this.disableCommand,
  });

  /// Builds the step from what the program gave it.
  factory DisableAddons.fromArguments(Arguments arguments) => DisableAddons(
    addons: arguments.textList('addons'),
    statusCommand: arguments.textList('status_command'),
    enableCommand: arguments.textList('enable_command'),
    disableCommand: arguments.textList('disable_command'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'addons',
      kind: ArgumentKind.textList,
      describes: 'the addons that must be off on this cluster, whatever switched them on',
    ),
    statusCommandArgument,
    // For the undo alone: cleaning up after a failure switches back on exactly what this run
    // switched off, and which command does that is as much the row's to write as the disable.
    enableCommandArgument,
    disableCommandArgument,
  ];

  /// The addons that must be off.
  final List<String> addons;

  /// The command that prints the state of the node with its addons.
  final List<String> statusCommand;

  /// The command an addon name is appended to in order to switch it back on, used by the undo.
  final List<String> enableCommand;

  /// The command an addon name is appended to in order to switch it off.
  final List<String> disableCommand;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (addons.isEmpty) {
      return const CheckResult.satisfied('no addon is declared to be off');
    }
    final Set<String>? on = await enabledAddons(context, statusCommand);
    if (on == null) {
      return const CheckResult.blocked(
        'the addons could not be read, so nothing says which of them are on',
      );
    }
    if (_stillOn(on).isEmpty) {
      return CheckResult.satisfied('${addons.join(', ')} are off');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final Set<String> on = await enabledAddons(context, statusCommand) ?? const <String>{};
    return StepPlan.argv(<String>[...disableCommand, ..._stillOn(on)]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final Set<String> on = await enabledAddons(context, statusCommand) ?? const <String>{};
    for (final String addon in _stillOn(on)) {
      final List<String> argv = <String>[...disableCommand, addon];
      final CommandResult switched = await context.shell.run(
        Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
      );
      if (!switched.ok) {
        throw CommandFailed(
          argv: argv,
          exitCode: switched.exitCode,
          stdout: switched.stdout,
          stderr: switched.stderr,
        );
      }
    }
  }

  /// The declared addons that are on, which are the ones the apply switches off.
  ///
  /// The undo switches exactly these back on. An addon that was already off — because the snap never
  /// switched it on, or because a previous run switched it off — would otherwise be switched on by
  /// an undo, and a program names an addon here in order not to run it.
  @override
  Future<List<String>> capture(StepContext context) async =>
      _stillOn(await enabledAddons(context, statusCommand) ?? const <String>{});

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    for (final String addon in captured) {
      final List<String> argv = <String>[...enableCommand, addon];
      await context.shell.run(
        Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
      );
    }
  }

  List<String> _stillOn(Set<String> on) => <String>[
    for (final String addon in addons)
      if (on.contains(addonNameIn(addon))) addonNameIn(addon),
  ];
}
