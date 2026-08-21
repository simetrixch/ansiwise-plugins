import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// Reading one field out of one answer: the value is published, the credential rides the header,
/// and nothing that is not a readable field ever passes for one.
void main() {
  const String address = 'https://one.example/api/things/a1';

  StepContext contextOn(
    Http http, {
    Measurements? measurements,
    Arguments answers = Arguments.none,
  }) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const NothingSaid(),
    step: const StepName('read_http_field'),
    arguments: Arguments.none,
    answers: answers,
    measurements: (measurements ?? Measurements()).forStep(
      const StepName('read_http_field'),
      ReadHttpField.publishes,
    ),
    facts: Facts.none,
  );

  ReadHttpField step({
    String url = address,
    String field = 'data.state',
    Map<String, Object?>? values,
    String? bearerAnswer,
  }) => ReadHttpField.fromArguments(
    Arguments(<String, Object>{
      'url': url,
      'field': field,
      'values': ?values,
      'bearer_answer': ?bearerAnswer,
      'timeout_seconds': 30,
    }),
  );

  test('the field is read, published, and the check is satisfied', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"data":{"state":"present"}}'),
    );
    final Measurements taken = Measurements();

    final CheckResult answer = await step().check(contextOn(http, measurements: taken));

    expect(answer, isA<Satisfied>());
    expect(taken.valueOf(const MeasurementName('http_field')), 'present');
    expect(http.sent.single.method, 'GET');
    expect(http.sent.single.url, address);
  });

  test('the credential the row names rides the authorization header, never the record', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"data":{"state":"present"}}'),
    );
    const Arguments answers = Arguments(<String, Object>{'api_credential': 's3cret-value'});

    await step(bearerAnswer: 'api_credential').check(contextOn(http, answers: answers));

    expect(http.sent.single.headers['authorization'], 'Bearer s3cret-value');
  });

  test('a slot of the address is filled from the answer the row binds it to', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"data":{"state":"present"}}'),
    );
    const Arguments answers = Arguments(<String, Object>{'api_host': 'one.example'});

    await step(
      url: 'https://<api-host>/api/things/a1',
      values: <String, Object?>{
        'api-host': <String, Object?>{'answer': 'api_host'},
      },
    ).check(contextOn(http, answers: answers));

    expect(http.sent.single.url, address);
  });

  test('an answer the run does not hold blocks the row by both names', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(200));

    final CheckResult answer = await step(
      url: 'https://<api-host>/a',
      values: <String, Object?>{
        'api-host': <String, Object?>{'answer': 'api_host'},
      },
    ).check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('api_host'));
    expect(http.sent, isEmpty);
  });

  test('an address still carrying a slot is refused before anything is sent', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(200));

    final CheckResult answer = await step(url: 'https://<api-host>/a').check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('<api-host>'));
    expect(http.sent, isEmpty);
  });

  test('a failure never passes for a value', () async {
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(500, 'boom'));
    final CheckResult answer = await step().check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('500'));
  });

  test('a missing field blocks rather than publishing an empty measurement', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"data":{}}'),
    );
    final Measurements taken = Measurements();

    final CheckResult answer = await step().check(contextOn(http, measurements: taken));

    expect(answer, isA<Blocked>());
    expect(taken.valueOf(const MeasurementName('http_field')), isNull);
  });

  test('it measures the same thing twice on a machine nothing was done to', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"data":{"state":"present"}}'),
    );
    final StepContext context = contextOn(http);

    expect(await step().check(context), isA<Satisfied>());
    expect(await step().check(context), isA<Satisfied>());
  });
}
