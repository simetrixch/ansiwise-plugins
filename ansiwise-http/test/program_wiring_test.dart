import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

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
}
