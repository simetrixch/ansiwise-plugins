import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// A step that decides on the STATUS an address answered, and can be wrong in both directions.
///
/// The step exists because the waiting step calls everything outside the two-hundreds "not yet",
/// which is what a store answers while it is standby, uninitialized or sealed. So the two things
/// measured here are opposite: that a status the row named as an answer IS accepted, and that a
/// status the row did not name is REFUSED — including one in the two-hundreds, because nothing is
/// implicitly acceptable.
void main() {
  const String address = 'https://store.example.com/v1/sys/health';

  ({StepContext context, Map<MeasurementName, String> published}) runOn(Http http) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(),
        http: http,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const NothingSaid(),
        step: const StepName('measure_http_status'),
        arguments: Arguments.none,
        answers: Arguments.none,
        facts: Facts.none,
        measurements: _Sink(published),
      ),
      published: published,
    );
  }

  MeasureHttpStatus asking({
    List<String> accepting = const <String>['200', '429', '501', '503'],
    String url = address,
  }) => MeasureHttpStatus.fromArguments(
    Arguments(<String, Object>{
      'asking_about': 'the store',
      'url': url,
      'accepting': accepting,
      'timeout_seconds': 5,
    }),
  );

  FakeHttp answering(int status) => FakeHttp()..answers('GET $address', status: status);

  group('a status the row named is accepted, and published', () {
    for (final int status in <int>[200, 429, 501, 503]) {
      test('$status is an answer, and the record says which', () async {
        final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(
          answering(status),
        );

        final CheckResult result = await asking().check(it.context);

        expect(result, isA<Satisfied>());
        expect((result as Satisfied).because, contains('$status'));
        expect(
          it.published[const MeasurementName('http_status')],
          '$status',
          reason: 'a later row tells "there and sealed" from "there and ready" by this value',
        );
      });
    }
  });

  group('a status the row did not name is refused', () {
    test('a 500 is refused, and the sentence names it and what the row accepts', () async {
      final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(
        answering(500),
      );

      final CheckResult result = await asking().check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, allOf(contains('500'), contains('200, 429, 501, 503')));
      expect(
        it.published,
        isEmpty,
        reason: 'nothing is published about a status this row did not accept',
      );
    });

    test('THE OTHER DIRECTION: a 200 is refused where the row did not name it', () async {
      // Nothing is implicitly acceptable. An interface that answers 200 with an error page is the
      // case this exists for, and a package that decided the two-hundreds are always fine would be
      // deciding it for every caller.
      final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(
        answering(200),
      );

      final CheckResult result = await asking(accepting: const <String>['503']).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, allOf(contains('200'), contains('503')));
    });
  });

  test('a reading that failed is neither, and says the address was never heard from', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(
      ScriptedHttp((HttpRequest request, int nth) => throw const SocketRefused()),
    );

    final CheckResult result = await asking().check(it.context);

    expect(result, isA<Blocked>());
    expect(
      (result as Blocked).reason,
      allOf(contains(address), contains('could not be asked')),
      reason: 'an operator must not be sent to look at a service that never heard the request',
    );
    expect(it.published, isEmpty);
  });

  test('a row holding no address is refused rather than asking nothing', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(FakeHttp());

    final CheckResult result = await asking(url: '').check(it.context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('no address'));
  });

  test('a row accepting nothing is refused rather than never being satisfiable', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOn(
      answering(200),
    );

    final CheckResult result = await asking(accepting: const <String>[]).check(it.context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('accepts no status'));
  });

  test('what the row says about the certificate reaches the request', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(200, ''));

    await MeasureHttpStatus.fromArguments(
      const Arguments(<String, Object>{
        'asking_about': 'the store',
        'url': address,
        'accepting': <String>['200'],
        'timeout_seconds': 5,
        'accepts_any_certificate': true,
      }),
    ).check(runOn(http).context);

    expect(http.sent.single.acceptsAnyCertificate, isTrue);
  });
}

/// What a port throws where the request could not be sent at all.
final class SocketRefused implements Exception {
  const SocketRefused();

  @override
  String toString() => 'connection refused';
}

final class _Sink implements MeasurementSink {
  const _Sink(this.published);

  final Map<MeasurementName, String> published;

  @override
  void publish(MeasurementName name, String value) => published[name] = value;
}
