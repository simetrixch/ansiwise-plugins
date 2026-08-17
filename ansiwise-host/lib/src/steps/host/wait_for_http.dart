import 'package:ansiwise_api/ansiwise_api.dart';

/// Waits until an address answers at all.
///
/// **What it is for.** A service the run has just brought up is reachable some time after the thing
/// that started it returned. The row that needs it says so here rather than the next row guessing:
/// a step that asks a service a question before it is listening gets a refusal that says nothing
/// about the service and everything about the timing.
///
/// **ANY ANSWER COUNTS, and that is the question being asked.** A redirect is an answer — a login
/// endpoint that sends a browser somewhere else is working exactly as intended, and the measured
/// case is precisely that: an identity provider answering 302 to every request, which is what it is
/// meant to do and what a wait for "2xx only" would call a failure forever. What this waits for is
/// something at the other end, not a particular thing to be said.
///
/// **It only measures.** The address is asked with a read, so a dry run may ask it too, and nothing
/// here changes anything at either end.
final class WaitForHttp extends ObservingStep with WaitStep {
  /// Polls [url] until it answers, giving up after [timeoutSeconds].
  const WaitForHttp({required this.url, required this.timeoutSeconds, this.intervalSeconds = 5});

  /// Builds the step from what the program gave it.
  factory WaitForHttp.fromArguments(Arguments arguments) => WaitForHttp(
    // OPTIONAL, AND NOT BECAUSE A ROW MAY LEAVE IT OUT. A row usually has this address from an
    // earlier measurement, and everything that examines a program before it runs has to build
    // every step — at that moment the measurement has not happened and the value does not exist.
    // Read as required, the whole program is refused before anything looks at anything.
    url: arguments.optionalText('url') ?? '',
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'url',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the address to wait for. A row that has it from an earlier measurement names that '
          'measurement instead, which is why this is not required: the program is examined before '
          'anything is measured, and a step that could not be built then would refuse the program',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to keep asking before giving up',
      required: false,
      defaultValue: 300,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between asks',
      required: false,
      defaultValue: 5,
    ),
  ];

  /// The address that is asked.
  final String url;

  /// How long the asking is given.
  final int timeoutSeconds;

  /// How long to leave between asks.
  final int intervalSeconds;

  @override
  String get waitingFor => '$url to answer';

  @override
  Duration get deadline => Duration(seconds: timeoutSeconds);

  @override
  Duration get interval => Duration(seconds: intervalSeconds);

  @override
  Future<({bool held, String? saw})> holds(StepContext context) async {
    // A GET is a read by its own definition, so the planning ports let it through and a dry run
    // asks the address too — which is the whole of what this step does.
    //
    // ONE ASK IS GIVEN THE GAP BETWEEN TWO ASKS, and no more. A poll that outlives the interval has
    // stopped being a poll: the next one is already due, and an address that cannot answer inside
    // that gap is not yet the thing being waited for.
    //
    // Any answer at all is the answer. An address that could not be reached does not come back with
    // a status, it throws — and the wait carries that reason to the deadline rather than losing it.
    await context.http.send(HttpRequest('GET', url, timeout: interval));
    return (held: true, saw: null);
  }
}
