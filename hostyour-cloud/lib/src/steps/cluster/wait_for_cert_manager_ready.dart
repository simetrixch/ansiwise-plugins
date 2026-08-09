import 'package:ansiwise_api/ansiwise_api.dart';

/// Waits for the certificate service to be able to accept the objects the next steps apply.
///
/// **The last part of it to come up is the one that admits those objects**, so it is what readiness
/// is decided on: while it is not running, applying a certificate issuer is refused by the API
/// server with a message about a webhook rather than about certificates.
///
/// **The fallback is for the versions whose parts are not labelled that way.** Where the part cannot
/// be picked out by name, three parts running is what says the service is up.
final class WaitForCertManagerReady extends ObservingStep {
  /// Waits up to [timeoutSeconds] for the certificate service in [namespace].
  const WaitForCertManagerReady({
    required this.namespace,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitForCertManagerReady.fromArguments(Arguments arguments) => WaitForCertManagerReady(
    namespace: arguments.text('namespace'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the certificate service runs in',
      required: false,
      defaultValue: defaultNamespace,
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long it is given to come up',
      required: false,
      defaultValue: 300,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks',
      required: false,
      defaultValue: 5,
    ),
  ];

  /// Where the certificate service runs.
  static const String defaultNamespace = 'cert-manager';

  /// How the part that admits certificate objects is labelled.
  static const String webhookSelector = 'app=webhook';

  /// How many parts running says the service is up where the label is missing.
  static const int fallbackRunningPods = 3;

  /// The namespace the service runs in.
  final String namespace;

  /// How long it is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    while (true) {
      if (await _webhookRunning(context)) {
        return const CheckResult.satisfied(
          'the part of the certificate service that admits certificate objects is running',
        );
      }
      final int running = await _runningPods(context);
      if (running >= fallbackRunningPods) {
        return CheckResult.satisfied(
          '$running parts of the certificate service are running, which is what says it is up on a '
          'version that does not label them',
        );
      }
      if (!context.clock.now().isBefore(giveUp)) {
        return CheckResult.blocked(
          'the certificate service in $namespace did not come up within ${timeoutSeconds}s — '
          '$running of its parts are running and the one that admits certificate objects is not '
          'among them',
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  Future<bool> _webhookRunning(StepContext context) async =>
      await _phases(context, <String>['-l', webhookSelector]) >= 1;

  Future<int> _runningPods(StepContext context) => _phases(context, const <String>[]);

  /// How many pods in the namespace matching [selector] are running.
  Future<int> _phases(StepContext context, List<String> selector) async {
    final CommandResult pods = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'pods',
        ...selector,
        '-o',
        r'jsonpath={range .items[*]}{.status.phase}{"\n"}{end}',
      ]),
    );
    if (!pods.ok) {
      return 0;
    }
    return pods.stdout.split('\n').where((String line) => line.trim() == 'Running').length;
  }
}
