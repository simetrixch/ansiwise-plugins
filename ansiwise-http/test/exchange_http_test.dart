import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// One changing request whose ANSWER is the whole of what it did.
///
/// **What is different from the step next door**, and every test here is about one of the three:
///
/// - there is NO already-probe. `send_http_request` reads the row's own `already_url` before it acts
///   and again afterwards as its proof; nothing an address could be asked says whether an exchange
///   has happened, because what would have to be read is the value the request handed back. So the
///   check sends nothing, answers only about the row, and never answers satisfied — and a second run
///   sends the request again, loudly.
/// - the proof is what it PUBLISHED. The engine reads that off the run's own measurements; what this
///   file measures is that the value really is published, from the answer to this row's own request.
/// - a read is not an exchange. The protocol's own words for a request that changes are the only
///   methods accepted, so a row cannot call a read an exchange and claim work where there is none.
void main() {
  const String address = 'https://one.example/api/sessions';

  StepContext contextOn(
    Http http, {
    Arguments answers = Arguments.none,
    Measurements? into,
    List<MeasurementSpec> publishes = const <MeasurementSpec>[],
    Logger log = const NothingSaid(),
  }) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: log,
    step: const StepName('exchange_http_field'),
    arguments: Arguments.none,
    answers: answers,
    measurements: (into ?? Measurements(Redactor(const <String>[]))).forStep(
      const StepName('exchange_http_field'),
      publishes,
    ),
    facts: Facts.none,
  );

  Arguments row({
    String method = 'POST',
    String url = address,
    String? socketPath,
    String? body,
    String? contentType,
    Map<String, Object?>? values,
    String? bearerAnswer,
    String? bearer,
    String field = 'data.credential',
  }) => Arguments(<String, Object>{
    'method': method,
    'url': url,
    'socket_path': ?socketPath,
    'body': ?body,
    'content_type': ?contentType,
    'values': ?values,
    'bearer_answer': ?bearerAnswer,
    'bearer': ?bearer,
    'field': field,
    'timeout_seconds': 30,
  });

  /// A network that hands back a different value every time it is asked, which is what a request of
  /// this kind does and what makes a second run a second one rather than a repeat.
  ScriptedHttp networkThatHandsBackAValue() => ScriptedHttp(
    (HttpRequest request, int nth) => answerOf(201, '{"data":{"credential":"value-$nth"}}'),
  );

  group('a read is not an exchange', () {
    for (final String reading in <String>['GET', 'HEAD', 'OPTIONS']) {
      test('$reading is refused as a method, before anything runs', () {
        // A row that could call a read an exchange would claim work, a value the other end made for
        // it, and a point of no return, where nothing was ever touched.
        expect(
          () => const ProgramResolver(httpRegistry).resolve(
            Program(
              name: const ProgramName('p'),
              roles: const <Role>[],
              steps: <ProgramStep>[
                ProgramStep(
                  step: const StepName('exchange_http_field'),
                  onFailure: OnFailure.exit,
                  arguments: row(method: reading),
                ),
              ],
            ),
          ),
          throwsA(
            isA<ProgramInvalid>().having(
              (ProgramInvalid failure) => '$failure',
              'message',
              contains('method'),
            ),
          ),
        );
      });
    }

    test('THE INNOCENT NEIGHBOUR: a changing method resolves', () {
      // Without this, a rule that refused every method would pass the three probes above.
      expect(
        const ProgramResolver(httpRegistry)
            .resolve(
              Program(
                name: const ProgramName('p'),
                roles: const <Role>[],
                steps: <ProgramStep>[
                  ProgramStep(
                    step: const StepName('exchange_http_field'),
                    onFailure: OnFailure.exit,
                    arguments: row(),
                  ),
                ],
              ),
            )
            .steps,
        hasLength(1),
      );
    });
  });

  group('the check answers about the ROW and is never the proof', () {
    test('a row that can be sent is ready, and nothing was sent to find that out', () async {
      final ScriptedHttp http = networkThatHandsBackAValue();

      expect(await ExchangeHttpField.fromArguments(row()).check(contextOn(http)), isA<Ready>());
      expect(
        http.sent,
        isEmpty,
        reason: 'a check that sent a request of this kind would have done the work to ask about it',
      );
    });

    test(
      'AND IT IS STILL READY AFTER THE APPLY, because nothing out there says otherwise',
      () async {
        // The whole of why this kind exists. Asked again, the step answers exactly what it answered
        // before — so the framework's ordinary postcondition would fail a row that worked, and the
        // engine reads what the row published instead.
        final ScriptedHttp http = networkThatHandsBackAValue();
        final StepContext context = contextOn(http, publishes: ExchangeHttpField.publishes);
        final ExchangeHttpField step = ExchangeHttpField.fromArguments(row());

        await step.apply(context);

        expect(await step.check(context), isA<Ready>());
        expect(http.sent.map((HttpRequest each) => each.method), <String>[
          'POST',
        ], reason: 'the check after the apply must not send a second one');
      },
    );

    test('a row whose credential this run does not hold is blocked, and names both', () async {
      final CheckResult answered = await ExchangeHttpField.fromArguments(
        row(bearerAnswer: 'api_credential'),
      ).check(contextOn(networkThatHandsBackAValue()));

      expect(answered, isA<Blocked>());
      expect((answered as Blocked).reason, contains('api_credential'));
    });

    test('a row with no address left after its slots are filled is blocked', () async {
      final CheckResult answered = await ExchangeHttpField.fromArguments(
        row(url: ''),
      ).check(contextOn(networkThatHandsBackAValue()));

      expect(answered, isA<Blocked>());
      expect((answered as Blocked).reason, contains('holds no address'));
    });

    test('a slot no text of the row spells is blocked, so a value cannot go nowhere', () async {
      final CheckResult answered =
          await ExchangeHttpField.fromArguments(
            row(
              values: <String, Object?>{
                'unused': <String, Object?>{'answer': 'api_host'},
              },
            ),
          ).check(
            contextOn(
              networkThatHandsBackAValue(),
              answers: const Arguments(<String, Object>{'api_host': 'one.example'}),
            ),
          );

      expect(answered, isA<Blocked>());
      expect((answered as Blocked).reason, contains('would go nowhere'));
    });
  });

  group('the apply sends one request and publishes what came back', () {
    test('composed exactly as the row wrote it', () async {
      final ScriptedHttp http = networkThatHandsBackAValue();
      final Measurements taken = Measurements(Redactor(const <String>[]));

      await ExchangeHttpField.fromArguments(
        row(
          url: 'https://<api-host>/api/sessions',
          body: '{"name":"<who>"}',
          contentType: 'application/json',
          values: <String, Object?>{
            'api-host': <String, Object?>{'answer': 'api_host'},
            'who': <String, Object?>{'answer': 'who'},
          },
          bearerAnswer: 'api_credential',
          socketPath: '/run/one/api.sock',
        ),
      ).apply(
        contextOn(
          http,
          answers: const Arguments(<String, Object>{
            'api_host': 'one.example',
            'who': 'a1',
            'api_credential': 'bearer-value',
          }),
          into: taken,
          publishes: ExchangeHttpField.publishes,
        ),
      );

      final HttpRequest only = http.sent.single;
      expect(only.method, 'POST');
      expect(only.url, address);
      expect(only.body, '{"name":"a1"}');
      expect(only.headers['authorization'], 'Bearer bearer-value');
      expect(only.headers['content-type'], 'application/json');
      expect(only.socketPath, '/run/one/api.sock');
      expect(taken.valueOf(const MeasurementName('http_exchanged_field')), 'value-0');
    });

    test('the credential a measurement filled rides the header', () async {
      // The handshake: what one exchange hands back is what the next request proves itself with.
      // The framework writes the value into the argument, so the step reads a value and learns
      // nothing about where it came from.
      final ScriptedHttp http = networkThatHandsBackAValue();

      await ExchangeHttpField.fromArguments(
        row(bearer: 'a-value-from-an-earlier-row'),
      ).apply(contextOn(http, publishes: ExchangeHttpField.publishes));

      expect(http.sent.single.headers['authorization'], 'Bearer a-value-from-an-earlier-row');
    });

    test('a row naming both sources for the credential is refused', () async {
      final CheckResult answered = await ExchangeHttpField.fromArguments(
        row(bearerAnswer: 'api_credential', bearer: 'a-value-from-an-earlier-row'),
      ).check(contextOn(networkThatHandsBackAValue()));

      expect(answered, isA<Blocked>());
      expect((answered as Blocked).reason, contains('name one of them'));
    });

    test('a second run makes a second one, and the values differ', () async {
      // Stated because it is the price of having no already-probe, and because a reader has to know
      // it before writing a program: rerunning re-sends.
      final ScriptedHttp http = networkThatHandsBackAValue();
      final Measurements taken = Measurements(Redactor(const <String>[]));
      final ExchangeHttpField step = ExchangeHttpField.fromArguments(row());

      await step.apply(contextOn(http, into: taken, publishes: ExchangeHttpField.publishes));
      final String? first = taken.valueOf(const MeasurementName('http_exchanged_field'));
      await step.apply(contextOn(http, into: taken, publishes: ExchangeHttpField.publishes));

      expect(http.sent, hasLength(2));
      expect(taken.valueOf(const MeasurementName('http_exchanged_field')), isNot(first));
    });
  });

  group('what an answer that cannot be published costs', () {
    test('a refused request throws, naming the method, the address and the status', () async {
      expect(
        () => ExchangeHttpField.fromArguments(row()).apply(
          contextOn(
            ScriptedHttp((HttpRequest request, int nth) => answerOf(409, 'already there')),
            publishes: ExchangeHttpField.publishes,
          ),
        ),
        throwsA(
          isA<RequestRefused>()
              .having((RequestRefused failure) => failure.status, 'status', 409)
              .having((RequestRefused failure) => failure.url, 'url', address),
        ),
      );
    });

    test('an answer with no value under the named field throws, naming the field', () async {
      expect(
        () => ExchangeHttpField.fromArguments(row(field: 'data.elsewhere')).apply(
          contextOn(
            ScriptedHttp(
              (HttpRequest request, int nth) => answerOf(201, '{"data":{"credential":"v"}}'),
            ),
            publishes: ExchangeHttpField.publishes,
          ),
        ),
        throwsA(
          isA<AnswerIncomplete>().having(
            (AnswerIncomplete failure) => failure.message,
            'message',
            allOf(contains('data.elsewhere'), contains('left nothing behind')),
          ),
        ),
      );
    });

    test('an answer that is not a JSON object throws rather than publishing nothing', () async {
      expect(
        () => ExchangeHttpField.fromArguments(row()).apply(
          contextOn(
            ScriptedHttp((HttpRequest request, int nth) => answerOf(201, 'not json at all')),
            publishes: ExchangeHttpField.publishes,
          ),
        ),
        throwsA(isA<AnswerIncomplete>()),
      );
    });
  });

  group('the two kinds differ in what they publish and in nothing else', () {
    test('one publishes a credential and the other does not', () {
      expect(ExchangeHttpField.publishes.single.secret, isFalse);
      expect(ExchangeHttpSecret.publishes.single.secret, isTrue);
      expect(
        ExchangeHttpSecret.arguments,
        same(ExchangeHttpField.arguments),
        reason: 'two kinds that took different arguments would be two grammars to keep in step',
      );
    });

    test('the registry says the same as the classes do', () {
      // A step's declaration and its registry entry are two places one fact is written, and only the
      // engine reads the second: a sink refuses a name the ENTRY does not declare, whatever the
      // class says.
      for (final (String name, List<MeasurementSpec> declared) in <(String, List<MeasurementSpec>)>[
        ('exchange_http_field', ExchangeHttpField.publishes),
        ('exchange_http_secret', ExchangeHttpSecret.publishes),
      ]) {
        final RegisteredStep entry = httpSteps[StepName(name)]!;
        expect(entry.publishes.single.name, declared.single.name, reason: name);
        expect(entry.publishes.single.secret, declared.single.secret, reason: name);
      }
    });

    test('THE SECRET ONE NEVER REPEATS WHAT CAME BACK, even where the other end refused', () async {
      // The one branch that could carry a value nothing hides yet: at the moment a request is
      // refused, nothing has been published and the redactor knows no value of this run.
      const String whatCameBack = 'a-value-nothing-registered';

      await expectLater(
        () => ExchangeHttpSecret.fromArguments(row()).apply(
          contextOn(
            ScriptedHttp((HttpRequest request, int nth) => answerOf(409, whatCameBack)),
            publishes: ExchangeHttpSecret.publishes,
          ),
        ),
        throwsA(
          isA<AnswerIncomplete>().having(
            (AnswerIncomplete failure) => failure.message,
            'message',
            allOf(
              contains('409'),
              contains(address),
              isNot(contains(whatCameBack)),
              contains('not repeated here'),
            ),
          ),
        ),
      );
    });

    test(
      'THE INNOCENT NEIGHBOUR: the other one does repeat it, so the rule above is a rule',
      () async {
        // Without this the assertion above would pass over a step that never carried the body at all,
        // and a clean answer would mean nobody was looking.
        const String whatCameBack = 'a-value-nothing-registered';

        await expectLater(
          () => ExchangeHttpField.fromArguments(row()).apply(
            contextOn(
              ScriptedHttp((HttpRequest request, int nth) => answerOf(409, whatCameBack)),
              publishes: ExchangeHttpField.publishes,
            ),
          ),
          throwsA(
            isA<RequestRefused>().having(
              (RequestRefused failure) => failure.body,
              'body',
              whatCameBack,
            ),
          ),
        );
      },
    );
  });
}
