import 'package:ansiwise_api/ansiwise_api.dart';
import 'enable_addons.dart';

/// Waits until every addon this cluster runs shows up as on.
///
/// Switching an addon on returns as soon as the request is accepted, and the status is what says
/// whether it took. This asks the status until it does or until the time is up.
///
/// **A timeout here is worth recording and not worth ending the run over.** What it says is that the
/// addon was asked for and has not appeared yet — which the steps after it will notice by themselves
/// if it really did not arrive, and which resolves on its own if it was only slow. What that costs
/// the run is the program row's declared policy and not this step's opinion.
///
/// **This is the one wait that cannot be a command and an answer.** What is on stands in the section
/// of the status between the heading for what is on and the heading for what is off, and the same
/// names are listed again under the second heading. A wait that looked for a name anywhere in the
/// output would find an addon in the list of what is OFF and report it as on — which is the state
/// every one of them is in at the moment this step starts looking. Knowing about the two sections is
/// what makes the reading right, and that knowledge is code rather than a line in a program file.
final class WaitForAddonsEnabled extends ObservingStep with WaitStep {
  /// Waits up to [timeoutSeconds] for each of [addons] to show up as on.
  const WaitForAddonsEnabled({
    required this.addons,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitForAddonsEnabled.fromArguments(Arguments arguments) => WaitForAddonsEnabled(
    addons: arguments.textList('addons'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'addons',
      kind: ArgumentKind.textList,
      describes: 'the addons that have to show up as on',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long they are given',
      required: false,
      defaultValue: 300,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks at the status',
      required: false,
      defaultValue: 5,
    ),
  ];

  /// The addons that have to show up.
  final List<String> addons;

  /// How long they are given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// The addons this is waiting for, all of them, because which ones are still off is read from the
  /// machine and a reached deadline is reported without looking again.
  @override
  String get waitingFor => '${addons.join(', ')} to show up as on';

  @override
  Duration get deadline => Duration(seconds: timeoutSeconds);

  @override
  Duration get interval => Duration(seconds: intervalSeconds);

  @override
  Future<bool> holds(StepContext context) async {
    final Set<String> on = await EnableAddons.enabled(context) ?? const <String>{};
    return addons.every(on.contains);
  }
}
