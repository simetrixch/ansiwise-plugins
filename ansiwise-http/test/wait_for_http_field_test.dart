import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// A wait that ends on a state: an arrived value satisfies it, a value the row names as final and
/// wrong ends it AT ONCE, and a reached deadline says what the last ask saw.
void main() {
  const String address = 'https://one.example/api/things/a1';

  StepContext contextOn(Http http, {FakeClock? clock, Arguments answers = Arguments.none}) =>
      StepContext(
        shell: FakeShell(),
        files: FakeFiles(),
        http: http,
        clock: clock ?? FakeClock(),
        entropy: FakeEntropy(),
        log: const NothingSaid(),
        step: const StepName('wait_for_http_field'),
        arguments: Arguments.none,
        answers: answers,
        facts: Facts.none,
      );

  WaitForHttpField step({
    String url = address,
    String field = 'state',
    List<String> until = const <String>['present'],
    List<String>? failing,
    int timeoutSeconds = 60,
    int intervalSeconds = 5,
  }) => WaitForHttpField.fromArguments(
    Arguments(<String, Object>{
      'waiting_for': 'the thing to be present',
      'url': url,
      'field': field,
      'until': until,
      'failing': ?failing,
      'timeout_seconds': timeoutSeconds,
      'interval_seconds': intervalSeconds,
    }),
  );

  test('an arrived value satisfies the check', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"present"}'),
    );
    final CheckResult answer = await step().check(contextOn(http));
    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains('present'));
  });

  test('anything in between is not yet, and every ask is a read', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(404));
    expect(await step().check(contextOn(http)), isA<Ready>());
    expect(http.sent.single.method, 'GET');
    expect(http.sent.single.observes, isTrue);
  });

  test('the wait polls until the state arrives, sleeping the row\'s interval', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) =>
          nth < 2 ? answerOf(404) : answerOf(200, '{"state":"present"}'),
    );
    final FakeClock clock = FakeClock();

    await step().apply(contextOn(http, clock: clock));

    expect(http.sent.length, 3);
    expect(clock.slept, everyElement(const Duration(seconds: 5)));
    expect(clock.slept.length, 2);
  });

  test('a state the row names as final and wrong ends the wait AT ONCE', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"broken"}'),
    );
    final FakeClock clock = FakeClock();

    await expectLater(
      step(failing: <String>['broken']).apply(contextOn(http, clock: clock)),
      throwsA(
        isA<StateError>().having(
          (StateError failure) => failure.message,
          'message',
          allOf(contains('broken'), contains('does not come back from')),
        ),
      ),
    );
    // At once: nothing was slept and nothing was asked twice — waiting out the window in front of
    // a state that never changes again is the defect this step exists to end.
    expect(clock.slept, isEmpty);
    expect(http.sent.length, 1);
  });

  test('the same final state blocks the check before anything runs', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"broken"}'),
    );
    expect(await step(failing: <String>['broken']).check(contextOn(http)), isA<Blocked>());
  });

  test('a reached deadline carries what the last ask saw', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"halfway"}'),
    );

    await expectLater(
      step(timeoutSeconds: 10, intervalSeconds: 5).apply(contextOn(http)),
      throwsA(
        isA<WaitedTooLong>().having(
          (WaitedTooLong failure) => failure.waitingFor,
          'waitingFor',
          contains('halfway'),
        ),
      ),
    );
  });

  test('an address that cannot be reached is the in-between, not a crash', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) =>
          nth == 0 ? throw StateError('connection refused') : answerOf(200, '{"state":"present"}'),
    );
    await step().apply(contextOn(http));
    expect(http.sent.length, 2);
  });

  test('a non-2xx answer with no JSON in it is the in-between too, and is waited through', () async {
    // The shape a reverse proxy in front of a service with no endpoint behind it produces: the
    // address resolves, something answers, and what answers is 503 with a line of prose. Until this
    // case was covered the suite knew 404 and a thrown connection error and no status in between,
    // so `readingOf` could have started calling this final without anything here noticing.
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) =>
          nth < 2 ? answerOf(503, 'Service Unavailable') : answerOf(200, '{"state":"present"}'),
    );
    final FakeClock clock = FakeClock();

    await step().apply(contextOn(http, clock: clock));

    expect(http.sent.length, 3);
    expect(clock.slept.length, 2);
  });

  test('and one that never stops answering 503 says so at the deadline', () async {
    // What the operator is left with when the wait does run out: the status the address kept
    // answering, rather than only the number of seconds that were spent on it.
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(503, 'Service Unavailable'),
    );

    await expectLater(
      step(timeoutSeconds: 10, intervalSeconds: 5).apply(contextOn(http)),
      throwsA(
        isA<WaitedTooLong>().having(
          (WaitedTooLong failure) => failure.waitingFor,
          'waitingFor',
          contains('503'),
        ),
      ),
    );
  });

  test('a value in until and in failing at once is refused, not raced', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(404));
    final CheckResult answer = await step(
      until: const <String>['present'],
      failing: <String>['present'],
    ).check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('opposite'));
    expect(http.sent, isEmpty);
  });
}
