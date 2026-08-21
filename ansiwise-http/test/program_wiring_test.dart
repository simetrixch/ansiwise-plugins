import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// The conversation as a PROGRAM: a row reads a field out of one answer, and a later row takes it
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
        row('read_http_field', <String, Object>{
          'url': 'https://one.example/api/things/a1',
          'field': 'links.watch',
        }),
        row(
          'wait_for_http_field',
          <String, Object>{
            'waiting_for': 'the thing to be present',
            'field': 'state',
            'until': <String>['present'],
          },
          reads: <String, MeasurementName>{'url': const MeasurementName('http_field')},
        ),
      ]),
    );

    expect(resolved.steps, hasLength(2));
    expect(resolved.steps[1].measured.single.measurement, const MeasurementName('http_field'));
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
            reads: <String, MeasurementName>{'url': const MeasurementName('http_field')},
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
            row('read_http_field', <String, Object>{'url': 'https://one.example/a', 'field': 'x'}),
            row('read_http_field', <String, Object>{'url': 'https://one.example/b', 'field': 'y'}),
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

    /// One row of each kind, each naming [socket] or leaving it off.
    Map<String, Map<String, Object>> rowsNaming(String? socket) => <String, Map<String, Object>>{
      'read_http_field': <String, Object>{'url': address, 'field': 'state', 'socket_path': ?socket},
      'send_http_request': <String, Object>{
        'method': 'POST',
        'url': address,
        'already_url': address,
        'already_field': 'state',
        'already_value': 'absent',
        'socket_path': ?socket,
      },
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
              row('read_http_field', <String, Object>{
                'url': address,
                'field': 'state',
                'socket_paths': socketFile,
              }),
            ]),
          ),
          throwsA(isA<ProgramInvalid>()),
        );
      },
    );
  });
}
