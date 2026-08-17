import 'package:ansiwise_api/ansiwise_api.dart';

import 'addon_status.dart';

/// Switches on the addons a program names, in the order it names them.
///
/// **The order is load-bearing and the failure of getting it wrong is completely silent.** The
/// access-control addon has to come first. Until it is on, the API server allows everything: every
/// access rule applied after it is accepted, looks correct, and enforces nothing — so every workload
/// can read every secret on the cluster, and nothing anywhere says so. Which addon that is, and
/// where it stands in the list, is the row's to write.
///
/// **An addon that takes arguments carries them in the request.** The snap takes an addon as its
/// name, or as its name, a colon and its arguments, and a row writes whichever of the two it means.
/// The arguments are only taken on the FIRST switch-on: after that they have no effect at all, and
/// the only thing that changes them is editing the object the addon installed.
///
/// **WHAT AN ADDON INSTALLED IS CHANGED BY CHANGING THE OBJECT, NEVER BY SWITCHING THE ADDON OFF AND
/// ON.** This was paid for on real machines.
///
/// - **The obvious fix is the one that fails.** On the snap this was learned on, switching an addon
///   off and on again is fragile from its 1.32 release onwards when it is driven from a script
///   rather than typed: the disable does not always finish before the enable starts, and what comes
///   back is a half-installed addon that reports success. Editing the object works on every version,
///   because what an addon leaves behind is an ordinary object in the cluster and nothing about it
///   is special.
/// - **The name service is the case this was learned on, and the failure is silent.** The cluster's
///   own name service inherits the machine's resolver file, which on some releases names the local
///   stub — and a pod's loopback is its own, not the machine's. So every lookup for anything outside
///   the cluster goes to an address that answers nothing from inside a pod, while the addon reports
///   itself enabled and healthy.
final class EnableAddons extends ReversibleStep<List<String>> {
  /// Switches on each of [addons], in order.
  const EnableAddons({
    required this.addons,
    required this.statusCommand,
    required this.enableCommand,
    required this.disableCommand,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory EnableAddons.fromArguments(Arguments arguments) => EnableAddons(
    addons: arguments.textList('addons'),
    statusCommand: arguments.textList('status_command'),
    enableCommand: arguments.textList('enable_command'),
    disableCommand: arguments.textList('disable_command'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'addons',
      kind: ArgumentKind.textList,
      describes:
          'the addons this cluster runs, in the order they are switched on — each written the way '
          'the snap takes it, which is the addon name, or the name, a colon and the arguments that '
          'addon is switched on with. Access control belongs first, or every access rule after it '
          'is accepted and enforces nothing',
    ),
    statusCommandArgument,
    enableCommandArgument,
    // For the undo alone: cleaning up after a failure switches off exactly what this run switched
    // on, and which command does that is as much the row's to write as the one that switched it on.
    disableCommandArgument,
    elevationArgument,
  ];

  /// The addons this cluster runs, as they are asked for.
  final List<String> addons;

  /// The command that prints the state of the node with its addons.
  final List<String> statusCommand;

  /// The command an addon request is appended to in order to switch it on.
  final List<String> enableCommand;

  /// The command an addon name is appended to in order to switch it off, used by the undo.
  final List<String> disableCommand;

  /// The names behind those requests, which is what the status answers under.
  List<String> get names => <String>[for (final String asked in addons) addonNameIn(asked)];

  /// Whether the tool this row drives refuses the account the run started as, so every
  /// question AND every switch it makes goes through elevation.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final Set<String>? on = await enabledAddons(context, statusCommand, elevated: elevated);
    if (on == null) {
      return const CheckResult.blocked(
        'the addons could not be read, so nothing says which of them are on',
      );
    }
    if (_missing(on).isEmpty) {
      return CheckResult.satisfied('${names.join(', ')} are on');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final Set<String> on =
        await enabledAddons(context, statusCommand, elevated: elevated) ?? const <String>{};
    return StepPlan.argv(<String>[...enableCommand, ..._missing(on)]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final Set<String> on =
        await enabledAddons(context, statusCommand, elevated: elevated) ?? const <String>{};
    // One at a time and in the order the program wrote them, so an addon that fails is named and
    // nothing after it is switched on against a cluster that is missing what comes before it.
    for (final String asked in _missing(on)) {
      final List<String> argv = <String>[...enableCommand, asked];
      final CommandResult switched = await context.shell.run(
        Command.detailed(argv.first, arguments: argv.sublist(1), elevated: elevated),
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

  /// The names of the declared addons that are off, which are the ones the apply switches on.
  ///
  /// The undo switches exactly these off again, and it needs the NAMES rather than the requests: an
  /// addon is switched off by its name, and the arguments a request carries mean nothing to a
  /// disable. An addon that was already running when this step ran keeps running — an undo happens
  /// while cleaning up after a failure, which is the worst moment to take away something that was
  /// there before.
  @override
  Future<List<String>> capture(StepContext context) async => <String>[
    for (final String asked in _missing(
      await enabledAddons(context, statusCommand, elevated: elevated) ?? const <String>{},
    ))
      addonNameIn(asked),
  ];

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    // In reverse, because the order they went on in is load-bearing: whatever the row put first is
    // switched off last.
    for (final String addon in captured.reversed) {
      final List<String> argv = <String>[...disableCommand, addon];
      await context.shell.run(
        Command.detailed(argv.first, arguments: argv.sublist(1), elevated: elevated),
      );
    }
  }

  /// The requests whose addon is not on yet.
  List<String> _missing(Set<String> on) => <String>[
    for (final String asked in addons)
      if (!on.contains(addonNameIn(asked))) asked,
  ];
}
