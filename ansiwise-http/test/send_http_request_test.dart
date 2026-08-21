import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// One changing request, gated on the read that says whether its state already stands: the
/// request is composed exactly as the row wrote it, the same read is the proof afterwards, and a
/// second run has nothing to do.
void main() {
  const String address = 'https://one.example/api/things';
  const String probe = 'https://one.example/api/things/a1';

  StepContext contextOn(Http http, {Arguments answers = Arguments.none}) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const NothingSaid(),
    step: const StepName('send_http_request'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  SendHttpRequest step({
    String method = 'POST',
    String url = address,
    String? socketPath,
    String? body,
    String? contentType,
    Map<String, Object?>? values,
    String? bearerAnswer,
    String alreadyUrl = probe,
    String alreadyField = 'state',
    String alreadyValue = 'present',
  }) => SendHttpRequest.fromArguments(
    Arguments(<String, Object>{
      'method': method,
      'url': url,
      'socket_path': ?socketPath,
      'body': ?body,
      'content_type': ?contentType,
      'values': ?values,
      'bearer_answer': ?bearerAnswer,
      'already_url': alreadyUrl,
      'already_field': alreadyField,
      'already_value': alreadyValue,
      'timeout_seconds': 30,
    }),
  );

  /// A network on which the state stands only once the request has been sent.
  ScriptedHttp networkThatChanges() {
    bool sent = false;
    return ScriptedHttp((HttpRequest request, int nth) {
      if (request.method == 'POST') {
        sent = true;
        return answerOf(201, '{"id":"a1"}');
      }
      return sent ? answerOf(200, '{"state":"present"}') : answerOf(404);
    });
  }

  test('nothing there means work, and the run proves itself by the same read', () async {
    final ScriptedHttp http = networkThatChanges();
    final StepContext context = contextOn(http);
    final SendHttpRequest row = step(body: '{"name":"a1"}', contentType: 'application/json');

    expect(await row.check(context), isA<Ready>());
    await row.apply(context);
    final CheckResult after = await row.check(context);

    expect(after, isA<Satisfied>());
    expect((after as Satisfied).because, contains('already stands'));
  });

  test('the request is composed exactly as the row wrote it', () async {
    final ScriptedHttp http = networkThatChanges();
    const Arguments answers = Arguments(<String, Object>{
      'api_host': 'one.example',
      'thing_credential': 's3cret-value',
      'api_credential': 'bearer-value',
    });
    final SendHttpRequest row = step(
      url: 'https://<api-host>/api/things',
      body: '{"name":"a1","credential":"<thing-credential>"}',
      contentType: 'application/json',
      values: <String, Object?>{
        'api-host': <String, Object?>{'answer': 'api_host'},
        'thing-credential': <String, Object?>{'answer': 'thing_credential'},
      },
      bearerAnswer: 'api_credential',
      alreadyUrl: 'https://<api-host>/api/things/a1',
    );
    final StepContext context = contextOn(http, answers: answers);

    expect(await row.check(context), isA<Ready>());
    await row.apply(context);

    final HttpRequest sent = http.sent.singleWhere((HttpRequest each) => each.method == 'POST');
    expect(sent.url, address);
    expect(sent.body, '{"name":"a1","credential":"s3cret-value"}');
    expect(sent.headers['authorization'], 'Bearer bearer-value');
    expect(sent.headers['content-type'], 'application/json');
    expect(sent.observes, isFalse);
  });

  test('a state that already stands is not sent again', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"present"}'),
    );

    expect(await step().check(contextOn(http)), isA<Satisfied>());
    expect(http.sent.single.method, 'GET');
  });

  test('a second run has nothing to do, proven on a network that changed once', () async {
    final ScriptedHttp http = networkThatChanges();
    final StepContext context = contextOn(http);
    final SendHttpRequest row = step();

    expect(await row.check(context), isA<Ready>());
    await row.apply(context);
    expect(await row.check(context), isA<Satisfied>());

    expect(await row.check(context), isA<Satisfied>());
    expect(http.sent.where((HttpRequest each) => each.method == 'POST').length, 1);
  });

  test('an unreadable probe never passes for "not yet"', () async {
    // The planted defect this guards: a 500 while probing read as absence, after which the request
    // is sent over whatever actually stands there.
    final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answerOf(500, 'boom'));
    final CheckResult answer = await step().check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('send the request over'));
  });

  test('a state that reads differently is still work', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) => answerOf(200, '{"state":"halfway"}'),
    );
    expect(await step().check(contextOn(http)), isA<Ready>());
  });

  test('a refused request is a failure that names the status', () async {
    final ScriptedHttp http = ScriptedHttp(
      (HttpRequest request, int nth) =>
          request.method == 'POST' ? answerOf(409, 'no') : answerOf(404),
    );
    final StepContext context = contextOn(http);

    await expectLater(
      step().apply(context),
      throwsA(isA<RequestRefused>().having((RequestRefused f) => f.status, 'status', 409)),
    );
  });

  test('the probe and the change alike go to the socket file the row named', () async {
    // No socket is opened here and none could be: this machine has none. What is measured is that
    // BOTH requests of the row carry the path — a row whose probe went over the network and whose
    // change went to the file would be reading one place and writing another.
    const String socketFile = '/run/one/api.sock';
    final ScriptedHttp http = networkThatChanges();
    final StepContext context = contextOn(http);
    final SendHttpRequest row = step(socketPath: socketFile);

    expect(await row.check(context), isA<Ready>());
    await row.apply(context);

    expect(http.sent.map((HttpRequest each) => each.socketPath), everyElement(socketFile));
    expect(http.sent.map((HttpRequest each) => each.method), contains('POST'));
  });

  test('a change over a socket is still a change, and a dry run refuses it', () async {
    final ScriptedHttp http = networkThatChanges();
    final Http planning = PlanningHttp(http, step: const StepName('send_http_request'));
    final SendHttpRequest row = step(socketPath: '/run/one/api.sock');

    await expectLater(
      row.apply(contextOn(planning)),
      throwsA(
        isA<MutationRefused>().having((MutationRefused f) => f.what, 'what', contains(address)),
      ),
    );
    expect(http.sent.where((HttpRequest each) => each.method == 'POST'), isEmpty);
  });

  test('it says what cannot be taken back, in the operator\'s words', () {
    expect(step().irreversibleReason, contains('stays changed'));
  });
}
