import 'package:ansiwise_api/ansiwise_api.dart';

/// Waits for the certificate issuer to report that its account is registered.
///
/// The object is accepted immediately; what takes time is the registration behind it, and until that
/// has happened no certificate on the cluster can be issued.
///
/// **A freshly applied issuer has no status at all**, which is different from having one that says
/// no. A reader that expects the conditions to be there fails on the very state it is meant to
/// report, so an absent status is read as not ready yet.
final class WaitClusterIssuerReady extends ObservingStep {
  /// Waits up to [timeoutSeconds] for [name] to report itself ready.
  const WaitClusterIssuerReady({
    required this.name,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitClusterIssuerReady.fromArguments(Arguments arguments) => WaitClusterIssuerReady(
    name: arguments.text('name'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the issuer every certificate on this cluster is issued by',
      required: false,
      defaultValue: 'letsencrypt-prod',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the registration is given',
      required: false,
      defaultValue: 60,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks',
      required: false,
      defaultValue: 10,
    ),
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// How long the registration is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    while (true) {
      if (await isReady(context, name)) {
        return CheckResult.satisfied('$name reports that its account is registered');
      }
      if (!context.clock.now().isBefore(giveUp)) {
        return CheckResult.blocked(
          '$name has not reported itself ready within ${timeoutSeconds}s, so no certificate on this '
          'cluster can be issued yet',
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  /// Whether [name] reports itself ready.
  ///
  /// Shared with the step that restarts the certificate service and applies the issuer again, so
  /// both ask the cluster the same question.
  ///
  /// An issuer that has just been applied carries no conditions at all, and reading them then gives
  /// nothing rather than an answer — which is not ready, and is not an error either.
  static Future<bool> isReady(StepContext context, String name) async {
    final CommandResult condition = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        'get',
        'clusterissuer',
        name,
        '-o',
        'jsonpath={.status.conditions[?(@.type=="Ready")].status}',
      ]),
    );
    return condition.ok && condition.trimmed == 'True';
  }
}
