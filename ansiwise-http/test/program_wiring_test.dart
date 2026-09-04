import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// The conversation as a PROGRAM: a row publishes a field out of one answer, and a later row takes
/// it
/// — through the framework's own wiring, with nothing computed in any file.
void main() {
  ProgramStep row(
    String step,
    Map<String, Object> arguments, {
    Map<String, MeasurementName> reads = const <String, MeasurementName>{},
  }) => ProgramStep(
    step: StepName(step),
    onFailure: OnFailure.exit,
    arguments: Arguments(arguments),
    reads: reads,
  );

  Program programOf(List<ProgramStep> steps) =>
      Program(name: const ProgramName('conversation'), roles: const <Role>[], steps: steps);

  test('a later row takes its address from the field an earlier row read', () {
    final ResolvedProgram resolved = const ProgramResolver(httpRegistry).resolve(
      programOf(<ProgramStep>[
        row('exchange_http_field', <String, Object>{
          'method': 'POST',
          'url': 'https://one.example/api/things',
          'field': 'links.watch',
        }),
        row(
          'wait_for_http_field',
          <String, Object>{
            'waiting_for': 'the thing to be present',
            'field': 'state',
            'until': <String>['present'],
          },
          reads: <String, MeasurementName>{'url': const MeasurementName('http_exchanged_field')},
        ),
      ]),
    );

    expect(resolved.steps, hasLength(2));
    expect(
      resolved.steps[1].measured.single.measurement,
      const MeasurementName('http_exchanged_field'),
    );
  });

  test('a row taking a field nothing publishes is refused before anything runs', () {
    expect(
      () => const ProgramResolver(httpRegistry).resolve(
        programOf(<ProgramStep>[
          row(
            'wait_for_http_field',
            <String, Object>{
              'waiting_for': 'the thing to be present',
              'field': 'state',
              'until': <String>['present'],
            },
            reads: <String, MeasurementName>{'url': const MeasurementName('http_exchanged_field')},
          ),
        ]),
      ),
      throwsA(
        isA<ProgramInvalid>().having(
          (ProgramInvalid failure) => '$failure',
          'message',
          contains('no step of this program publishes it'),
        ),
      ),
    );
  });

  test(
    'TWO reading rows in one program are refused: the published name is fixed per step kind',
    () {
      // This is the measured limit of the framework as it stands, held here so its lifting is
      // noticed: a program that has to carry two different values out of two answers cannot be
      // written until a row can rename what it publishes.
      expect(
        () => const ProgramResolver(httpRegistry).resolve(
          programOf(<ProgramStep>[
            row('exchange_http_field', <String, Object>{
              'method': 'POST',
              'url': 'https://one.example/a',
              'field': 'x',
            }),
            row('exchange_http_field', <String, Object>{
              'method': 'POST',
              'url': 'https://one.example/b',
              'field': 'y',
            }),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => '$failure',
            'message',
            contains('is published by'),
          ),
        ),
      );
    },
  );

  /// A row that names a socket file, all the way down to the request the port is handed.
  ///
  /// NOTHING HERE REACHES A SOCKET, and nothing here could: the machine this suite runs on has no
  /// unix domain sockets at all. What is measured is the composition — the row names a path, the
  /// resolver carries it, the step writes it into the request, and the port sees it. That the
  /// bytes then arrive at that file is the network port's half, provable only where such a socket
  /// exists.
  group('a row names the socket file its requests go to', () {
    const String address = 'https://one.example/api/things/a1';
    const String socketFile = '/run/one/api.sock';

    /// Every request one row sends while its check runs, with the step built by the resolver.
    Future<List<HttpRequest>> requestsOf(String step, Map<String, Object> arguments) async {
      final ResolvedProgram resolved = const ProgramResolver(
        httpRegistry,
      ).resolve(programOf(<ProgramStep>[row(step, arguments)]));
      final ResolvedStep only = resolved.steps.single;
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answerOf(200, '{"state":"present"}'),
      );

      await only.registered
          .create(only.argumentsWithDefaults)
          .check(
            StepContext(
              shell: FakeShell(),
              files: FakeFiles(),
              http: http,
              clock: FakeClock(),
              entropy: FakeEntropy(),
              log: const NothingSaid(),
              step: only.registered.name,
              arguments: Arguments.none,
              answers: Arguments.none,
              measurements: Measurements(
                Redactor(const <String>[]),
              ).forStep(only.registered.name, only.registered.publishes),
              facts: Facts.none,
            ),
          );
      return http.sent;
    }

    /// Every row kind that sends while its check runs, each naming [socket] or leaving it off.
    ///
    /// One today. The two exchange kinds send from their APPLY and nothing at all from their check,
    /// which is what their kind means, so a request of theirs is not what this group measures.
    Map<String, Map<String, Object>> rowsNaming(String? socket) => <String, Map<String, Object>>{
      'wait_for_http_field': <String, Object>{
        'waiting_for': 'the thing to be present',
        'url': address,
        'field': 'state',
        'until': <String>['present'],
        'socket_path': ?socket,
      },
    };

    for (final MapEntry<String, Map<String, Object>> each in rowsNaming(socketFile).entries) {
      test('${each.key} hands the port a request carrying the path the row named', () async {
        final List<HttpRequest> sent = await requestsOf(each.key, each.value);

        expect(sent, isNotEmpty);
        expect(sent.map((HttpRequest request) => request.socketPath), everyElement(socketFile));
        // The address is untouched by it: it still supplies the path and the host header.
        expect(sent.map((HttpRequest request) => request.url), everyElement(address));
      });
    }

    for (final MapEntry<String, Map<String, Object>> each in rowsNaming(null).entries) {
      test('${each.key} carries no path where the row named none', () async {
        final List<HttpRequest> sent = await requestsOf(each.key, each.value);

        expect(sent, isNotEmpty);
        expect(sent.map((HttpRequest request) => request.socketPath), everyElement(isNull));
      });
    }

    test(
      'a name no step declares is refused, which is what makes the rows above mean anything',
      () {
        // Without this the tests above would pass over an argument nothing declared: an unread key
        // and an unnamed socket produce the same null, and the row would look honoured either way.
        expect(
          () => const ProgramResolver(httpRegistry).resolve(
            programOf(<ProgramStep>[
              row('wait_for_http_field', <String, Object>{
                'waiting_for': 'the thing to be present',
                'url': address,
                'field': 'state',
                'until': <String>['present'],
                'socket_paths': socketFile,
              }),
            ]),
          ),
          throwsA(isA<ProgramInvalid>()),
        );
      },
    );
  });

  /// What fills a row's texts, from the two places a value can come from.
  ///
  /// An answer the run was started with, and a value an earlier row published. Both arrive through
  /// the same mapping, so both are measured the same way: what the port was handed.
  group('a row fills its texts from what the run holds', () {
    const String socketFile = '/run/one/api.sock';

    /// Every request one row sends while its check runs, with [answers] standing for the run's.
    Future<List<HttpRequest>> requestsOf(
      String step,
      Map<String, Object> arguments, {
      Arguments answers = Arguments.none,
    }) async {
      final ResolvedProgram resolved = const ProgramResolver(httpRegistry).resolve(
        Program(
          name: const ProgramName('conversation'),
          roles: const <Role>[],
          steps: <ProgramStep>[row(step, arguments)],
          answers: const DeclaredAnswers(<ArgumentSpec>[
            ArgumentSpec(
              name: 'admin_socket_path',
              kind: ArgumentKind.text,
              describes: 'where the socket file stands on this machine',
            ),
          ]),
        ),
      );
      final ResolvedStep only = resolved.steps.single;
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answerOf(200, '{"state":"present"}'),
      );

      await only.registered
          .create(only.argumentsWithDefaults)
          .check(
            StepContext(
              shell: FakeShell(),
              files: FakeFiles(),
              http: http,
              clock: FakeClock(),
              entropy: FakeEntropy(),
              log: const NothingSaid(),
              step: only.registered.name,
              arguments: Arguments.none,
              answers: answers,
              measurements: Measurements(
                Redactor(const <String>[]),
              ).forStep(only.registered.name, only.registered.publishes),
              facts: Facts.none,
            ),
          );
      return http.sent;
    }

    test('a slot of the socket file is filled from the answer the row names', () async {
      final List<HttpRequest> sent = await requestsOf('wait_for_http_field', <String, Object>{
        'waiting_for': 'the thing to be present',
        'url': 'https://one.example/api/things/a1',
        'field': 'state',
        'until': <String>['present'],
        'socket_path': '<admin-socket>',
        'values': <String, Object?>{
          'admin-socket': <String, Object?>{'answer': 'admin_socket_path'},
        },
      }, answers: const Arguments(<String, Object>{'admin_socket_path': socketFile}));

      expect(sent, isNotEmpty);
      expect(sent.map((HttpRequest request) => request.socketPath), everyElement(socketFile));
    });

    test(
      'a socket file still carrying a slot is refused rather than opened by that name',
      () async {
        final List<HttpRequest> sent = await requestsOf('wait_for_http_field', <String, Object>{
          'waiting_for': 'the thing to be present',
          'url': 'https://one.example/api/things/a1',
          'field': 'state',
          'until': <String>['present'],
          'socket_path': '<admin-socket>',
        });

        expect(
          sent,
          isEmpty,
          reason:
              'a path left with its slot in would be opened as those literal characters, and the '
              'failure would read as a socket that is not there',
        );
      },
    );

    /// The credential a run mints, on a row that only WATCHES.
    ///
    /// A poll of a guarded address is the second half of every handshake: something is made, and
    /// then it is watched until it settles. Without this the watching rows could carry only what an
    /// operator typed, and a program that minted its own credential could not read back what it had
    /// just made with it.
    test('a watching row carries the credential an earlier row minted', () async {
      final List<HttpRequest> sent = await requestsOf('wait_for_http_field', <String, Object>{
        'waiting_for': 'the thing to be present',
        'url': 'https://one.example/api/things/a1',
        'field': 'state',
        'until': <String>['present'],
        // What the framework writes in where the row named a secret measurement.
        'bearer': 'sess-9f2b',
      });

      expect(
        sent.map((HttpRequest request) => request.headers['authorization']),
        everyElement('Bearer sess-9f2b'),
      );
    });

    test('a watching row filling its bearer from a value nothing declared secret is refused', () {
      expect(
        () => const ProgramResolver(httpRegistry).resolve(
          programOf(<ProgramStep>[
            row('exchange_http_field', <String, Object>{
              'method': 'POST',
              'url': 'https://one.example/api/sessions',
              'field': 'credential',
            }),
            row(
              'wait_for_http_field',
              <String, Object>{
                'waiting_for': 'the thing to be present',
                'url': 'https://one.example/api/things/a1',
                'field': 'state',
                'until': <String>['present'],
              },
              reads: <String, MeasurementName>{
                'bearer': const MeasurementName('http_exchanged_field'),
              },
            ),
          ]),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => '$failure',
            'message',
            contains('"bearer" is secret while that measurement is not'),
          ),
        ),
      );
    });

    /// The carried value, all the way from the row that publishes it to the request that sends it.
    ///
    /// This is what a program needs to speak twice to one interface about one thing it just made:
    /// the first row learns the name of it and the second addresses it. The resolver reads
    /// `{measured: ...}`, the engine writes the value in where that body stood, and the step reads
    /// the value as though the row had written it out.
    test('a slot of the address is filled from what an earlier row published', () async {
      final ResolvedProgram resolved = const ProgramResolver(httpRegistry).resolve(
        programOf(<ProgramStep>[
          row('exchange_http_field', <String, Object>{
            'method': 'POST',
            'url': 'https://one.example/api/things',
            'field': 'id',
          }),
          row('wait_for_http_field', <String, Object>{
            'waiting_for': 'the thing to be present',
            'url': 'https://one.example/api/things/<thing-id>',
            'field': 'state',
            'until': <String>['present'],
            'values': <String, Object?>{
              'thing-id': <String, Object?>{'measured': 'http_exchanged_field'},
            },
          }),
        ]),
      );

      expect(
        resolved.steps[1].measuredSlots.single.measurement,
        const MeasurementName('http_exchanged_field'),
      );

      // What the engine hands the step once the earlier row has published: the value written in
      // where the body stood.
      final List<HttpRequest> sent = await requestsOf('wait_for_http_field', <String, Object>{
        'waiting_for': 'the thing to be present',
        'url': 'https://one.example/api/things/<thing-id>',
        'field': 'state',
        'until': <String>['present'],
        'values': <String, Object?>{'thing-id': 'a1'},
      });

      expect(
        sent.map((HttpRequest request) => request.url),
        everyElement('https://one.example/api/things/a1'),
      );
    });
  });
}
