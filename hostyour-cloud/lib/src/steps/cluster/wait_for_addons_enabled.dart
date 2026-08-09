import 'package:ansiwise_api/ansiwise_api.dart';
import 'enable_addons.dart';

/// Waits until every addon this cluster runs shows up as on.
///
/// Switching an addon on returns as soon as the request is accepted, and the status is what says
/// whether it took. This asks the status until it does or until the time is up.
///
/// **A timeout here is worth recording and not worth ending the run over.** What it says is that the
/// addon was asked for and has not appeared yet — which the steps after it will notice by themselves
/// if it really did not arrive, and which resolves on its own if it was only slow.
final class WaitForAddonsEnabled extends ObservingStep {
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

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    List<String> missing = addons;

    while (true) {
      final Set<String> on = await EnableAddons.enabled(context) ?? const <String>{};
      missing = <String>[
        for (final String addon in addons)
          if (!on.contains(addon)) addon,
      ];
      if (missing.isEmpty) {
        return CheckResult.satisfied('${addons.join(', ')} are on');
      }
      if (!context.clock.now().isBefore(giveUp)) {
        return CheckResult.blocked(
          '${missing.join(', ')} were switched on and have not shown up as on within '
          '${timeoutSeconds}s',
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }
}
