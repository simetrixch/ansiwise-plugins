import 'package:ansiwise_api/ansiwise_api.dart';

/// Waits for an HTTP endpoint to return a success status code.
///
/// **The address is polled until it answers.** Services take time to start, and a
/// deployment tool should not fail just because a service is still initializing.
///
/// **The URL can contain placeholders.** If the URL contains `<answer_name>`, it will
/// be replaced with the value of the answer with that name from the current run.
final class WaitForHttp extends ObservingStep {
  /// Polls [url] until it returns a 2xx status code.
  const WaitForHttp({
    required this.url,
    required this.timeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitForHttp.fromArguments(Arguments arguments) => WaitForHttp(
    url: arguments.optionalText('url') ?? '',
    timeoutSeconds: arguments.integer('timeout_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      describes: 'the URL to poll. Placeholders like <answer_name> are replaced with answer values.',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to wait before giving up',
      required: false,
      defaultValue: 300,
    ),
  ];

  /// The URL to poll.
  final String url;

  /// The timeout in seconds.
  final int timeoutSeconds;

  /// Replaces `<answer_name>` with the value of `answer_name` from [context].
  String _interpolateUrl(StepContext context) {
    String filled = url;
    final RegExp slotExp = RegExp(r'<([^>]+)>');
    for (final Match match in slotExp.allMatches(url)) {
      final String slot = match.group(0)!;
      final String answerName = match.group(1)!;
      final String value = context.answers.text(answerName);
      filled = filled.replaceAll(slot, value);
    }
    return filled;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    return const CheckResult.ready();
  }

  @override
  Future<void> apply(StepContext context) async {
    final String resolvedUrl = _interpolateUrl(context);
    
    final int end = DateTime.now().millisecondsSinceEpoch + (timeoutSeconds * 1000);
    int delayMs = 1000;
    
    while (DateTime.now().millisecondsSinceEpoch < end) {
      final Command cmd = Command(
        'curl',
        <String>['-s', '-o', '/dev/null', '-w', '%{http_code}', resolvedUrl],
      );
      
      final CommandResult result = await context.shell.run(cmd);
      
      if (result.ok) {
        final String stdout = result.stdout.trim();
        if (stdout.startsWith('2') || stdout.startsWith('3')) {
          return;
        }
      }
      
      await Future<void>.delayed(Duration(milliseconds: delayMs));
      // Backoff up to 10 seconds
      if (delayMs < 10000) delayMs *= 2;
    }
    
    throw CommandFailed(
      argv: <String>['curl', resolvedUrl],
      exitCode: 1,
      stdout: '',
      stderr: 'Timed out waiting for $resolvedUrl after $timeoutSeconds seconds',
    );
  }
}
