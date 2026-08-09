import 'package:ansiwise_api/ansiwise_api.dart';

/// Refuses to go on until the node answers that it is running.
///
/// Everything after this talks to an API server, and an API server that is not up yet answers a
/// connection refused rather than an error anyone can act on. Waiting here once turns a scattering
/// of unexplained failures further down into one line that says what was not ready.
///
/// **The wait is the snap's own, and it only looks.** `microk8s status --wait-ready` blocks until
/// the node reports itself running and changes nothing while it does, so it is declared as observing
/// and a dry run may run it. The verdict comes from what the status says, never from the exit code:
/// the command returns zero on a node that answered, and this reads the answer.
final class WaitForMicrok8sReady extends ObservingStep {
  /// Waits up to [timeoutSeconds] for the node to report itself running.
  const WaitForMicrok8sReady({required this.timeoutSeconds});

  /// Builds the step from what the program gave it.
  factory WaitForMicrok8sReady.fromArguments(Arguments arguments) =>
      WaitForMicrok8sReady(timeoutSeconds: arguments.integer('timeout_seconds'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the node is given to come up before the run gives up on it',
      required: false,
      defaultValue: 300,
    ),
  ];

  /// What the snap prints when the node is up.
  static const String runningLine = 'microk8s is running';

  /// How long the node is given.
  final int timeoutSeconds;

  @override
  bool get verifiesAnEarlierStep => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult status = await context.shell.run(
      Command.detailed(
        'microk8s',
        arguments: <String>['status', '--wait-ready', '--timeout', '$timeoutSeconds'],
        observes: true,
        timeout: Duration(seconds: timeoutSeconds + _grace),
      ),
    );
    if (status.ok && status.stdout.contains(runningLine)) {
      return const CheckResult.satisfied('the node reports that it is running');
    }
    return CheckResult.blocked(
      'the node did not report itself running within ${timeoutSeconds}s: '
      '${_firstLine(status.stdout.isEmpty ? status.stderr : status.stdout)}',
    );
  }

  static String _firstLine(String output) {
    final String trimmed = output.trim();
    if (trimmed.isEmpty) {
      return 'it said nothing at all';
    }
    return trimmed.split('\n').first.trim();
  }

  /// How much longer this framework waits than the command it is waiting on.
  ///
  /// Without it the two deadlines race, and the one that fires is the outer one — which reports a
  /// framework timeout instead of the command's own message about what was not ready.
  static const int _grace = 30;
}
