import 'package:ansiwise_core/ansiwise_core.dart';

import 'addon_status.dart';

/// Waits until every addon a row names shows up as on.
///
/// Switching an addon on returns as soon as the request is accepted, and the status is what says
/// whether it took. This asks the status until it does or until the time is up.
///
/// **A timeout here is worth recording and not worth ending the run over.** What it says is that the
/// addon was asked for and has not appeared yet — which the steps after it will notice by themselves
/// if it really did not arrive, and which resolves on its own if it was only slow. What that costs
/// the run is the program row's declared policy and not this step's opinion.
///
/// **THIS IS THE ONE WAIT THAT CANNOT BE A COMMAND AND AN ANSWER, and the reason is the answer a
/// stopped node gives.** Two things stand in the way of a generic wait:
///
/// - **The exit code says nothing.** The snap's status exits ZERO on a node that is not running: it
///   prints that it is stopped, tells the operator to start it, and returns success. A wait built on
///   the exit code would be satisfied by a cluster that is down.
/// - **A line of the output is not enough either.** What is on stands in the section between the
///   heading for what is on and the heading for what is off, and the SAME names are listed again
///   under the second heading. A wait that looked for a name anywhere in the output would find the
///   addon under "disabled" and report it as on — which is the state every one of them is in at the
///   moment this step starts looking.
///
/// So what is measured is the OUTPUT, read section by section. That knowledge is code rather than a
/// line in a program file.
final class WaitForAddonsEnabled extends ObservingStep with WaitStep {
  /// Waits up to [timeoutSeconds] for each of [addons] to show up as on.
  const WaitForAddonsEnabled({
    required this.addons,
    required this.statusCommand,
    required this.timeoutSeconds,
    required this.intervalSeconds,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory WaitForAddonsEnabled.fromArguments(Arguments arguments) => WaitForAddonsEnabled(
    addons: arguments.textList('addons'),
    statusCommand: arguments.textList('status_command'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'addons',
      kind: ArgumentKind.textList,
      describes:
          'the addons that have to show up as on — written as their names, or as the same requests '
          'the row switching them on writes, of which only the name is held against the status',
    ),
    statusCommandArgument,
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long they are given before the wait reports that it did not happen',
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks at the status',
    ),
    elevationArgument,
  ];

  /// The addons that have to show up.
  final List<String> addons;

  /// The command that prints the state of the node with its addons.
  final List<String> statusCommand;

  /// How long they are given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// The names behind those requests, which is what the status answers under.
  ///
  /// A row is free to write the same list the switching row writes, arguments and all — holding the
  /// whole request against the status would wait for a name the snap never prints, forever.
  List<String> get names => <String>[for (final String asked in addons) addonNameIn(asked)];

  /// The addons this is waiting for, all of them, because which ones are still off is read from the
  /// machine and a reached deadline is reported without looking again.

  /// Whether the tool this row drives refuses the account the run started as, so every
  /// question AND every switch it makes goes through elevation.
  final bool elevated;

  @override
  String get waitingFor => '${names.join(', ')} to show up as on';

  @override
  Duration get deadline => Duration(seconds: timeoutSeconds);

  @override
  Duration get interval => Duration(seconds: intervalSeconds);

  @override
  Future<({bool held, String? saw})> holds(StepContext context) async {
    // The OUTPUT and not the exit code, and the enabled section of it and not the whole. A node that
    // is not running exits zero and prints no such section, so it names nothing here and the wait
    // goes on rather than ending on a cluster that is down.
    final Set<String> on =
        await enabledAddons(context, statusCommand, elevated: elevated) ?? const <String>{};
    final List<String> missing = <String>[
      for (final String name in names)
        if (!on.contains(name)) name,
    ];
    if (missing.isEmpty) {
      return (held: true, saw: null);
    }
    // The addons still off, by name. A wait that reports only its own duration sends an operator to
    // read a whole status page for the one line this already has.
    return (
      held: false,
      saw: on.isEmpty
          ? 'the node named no addon as on at all, which is what a node that is not running says'
          : '${missing.join(', ')} ${missing.length == 1 ? 'is' : 'are'} still off, and '
                '${on.join(', ')} ${on.length == 1 ? 'is' : 'are'} on',
    );
  }
}
