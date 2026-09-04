import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// THE PROOF: a credential that did not exist when the run started, carried to a second request, and
/// in no line of the record that run left behind.
///
/// **What is being held together here.** One row asks the other end for a credential and publishes
/// what came back under a name its registry entry declares SECRET — so the run's own sink registers
/// the value with the redactor at the moment it is published. The next row takes that value into an
/// argument the step declares secret and sends it as a bearer. Then every line of the finished
/// record is read: the events an operator tails and the header they paste into a message.
///
/// **Three things are asserted and none of them is enough alone.** That the value really rode the
/// second request, or a clean record would only mean nothing was carried. That it stands in no line.
/// And that the record carries the redaction marker, or a clean record would only mean the value
/// never reached a recording surface at all.
///
/// **The innocent neighbour is the same conversation with the same network, published by the kind
/// that does NOT declare a credential** — and there the value IS in the record, in the line the
/// watching row writes about what it read. That line is the surface: an interface that echoes a
/// session identifier back in a status field is entirely ordinary, and the redactor is the only
/// thing between it and a world-readable file.
void main() {
  /// What the other end hands back, chosen so that finding it anywhere is unambiguous.
  const String credential = 'sess-9f2b-this-must-be-in-no-record';

  const String sessions = 'https://one.example/api/sessions';
  const String thing = 'https://one.example/api/things/a1';

  /// The other end: it hands back a credential, and reports it as the state of the thing.
  ScriptedHttp otherEnd() => ScriptedHttp((HttpRequest request, int nth) {
    if (request.url == sessions) {
      return answerOf(201, '{"data":{"credential":"$credential"}}');
    }
    if (request.url == thing) {
      // ECHOED BACK, which is what makes this test bite. The row that watches this address writes
      // what it found into the record, and only the redactor stands between that line and the file.
      return answerOf(200, '{"state":"$credential"}');
    }
    return answerOf(201, '{}');
  });

  ProgramStep exchanging(String step) => ProgramStep(
    step: StepName(step),
    onFailure: OnFailure.exit,
    arguments: const Arguments(<String, Object>{
      'method': 'POST',
      'url': sessions,
      'field': 'data.credential',
    }),
  );

  /// The watching row: it carries the credential as a bearer and reports the state it finds.
  ///
  /// `until_present` rather than a value, so what ends the wait is the field carrying anything at
  /// all - which is what puts the value it read into the line the record keeps.
  ProgramStep watching({Map<String, MeasurementName> reads = const <String, MeasurementName>{}}) =>
      ProgramStep(
        step: const StepName('wait_for_http_field'),
        onFailure: OnFailure.exit,
        arguments: const Arguments(<String, Object>{
          'waiting_for': 'the thing to report a state',
          'url': thing,
          'field': 'state',
          'until_present': true,
        }),
        reads: reads,
      );

  late Directory temp;
  late RunDirectory directory;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('ansiwise-exchange-secret-');
    directory = RunDirectory(temp.path);
  });

  tearDown(() async {
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      // Windows can hold a handle open for a moment after a file is closed.
    }
  });

  /// Runs [steps] through the real engine and answers with the record it left and the network it
  /// spoke to.
  Future<({List<String> lines, ScriptedHttp http, RunRecord record})> runOf(
    List<ProgramStep> steps,
  ) async {
    final FakeClock clock = FakeClock();
    final ScriptedHttp http = otherEnd();
    final Redactor redactor = Redactor(const <String>[]);
    final FileRecorder recorder = await FileRecorder.open(
      id: _id,
      directory: directory,
      clock: clock,
      redactor: redactor,
    );
    final ResolvedProgram program = const ProgramResolver(httpRegistry).resolve(
      Program(
        name: const ProgramName('conversation'),
        roles: const <Role>[Role('master')],
        steps: steps,
      ),
    );

    final RunRecord closed = await Runner(
      machine: Machine(
        shell: FakeShell(),
        files: FakeFiles(),
        http: http,
        clock: clock,
        entropy: FakeEntropy(),
      ),
      recorder: recorder,
      redactor: redactor,
    ).run(program: program, mode: Mode.run, header: _header(clock));
    await recorder.close();
    await recorder.save(closed);

    return (
      lines: <String>[
        ...File(directory.events(_id)).readAsLinesSync(),
        ...File(directory.header(_id)).readAsLinesSync(),
      ].where((String line) => line.isNotEmpty).toList(growable: false),
      http: http,
      record: closed,
    );
  }

  test('the conversation holds: one row asks for the credential, the next sends it', () async {
    final ({List<String> lines, ScriptedHttp http, RunRecord record}) run = await runOf(
      <ProgramStep>[
        exchanging('exchange_http_secret'),
        watching(
          reads: const <String, MeasurementName>{
            'bearer': MeasurementName('http_exchanged_secret'),
          },
        ),
      ],
    );

    expect(
      run.record.exitCode,
      0,
      reason: 'both rows have to have worked for the rest to mean much',
    );
    final Iterable<HttpRequest> watched = run.http.sent.where(
      (HttpRequest each) => each.url == thing,
    );
    expect(watched, isNotEmpty, reason: 'the watching row has to have asked for the rest to bite');
    expect(
      watched.map((HttpRequest each) => each.headers['authorization']),
      everyElement('Bearer $credential'),
      reason:
          'the value really rode the second request, or a record without it in would say nothing at '
          'all',
    );
  });

  test('THE VALUE IS IN NO LINE OF THE FINISHED RECORD', () async {
    final ({List<String> lines, ScriptedHttp http, RunRecord record}) run = await runOf(
      <ProgramStep>[
        exchanging('exchange_http_secret'),
        watching(
          reads: const <String, MeasurementName>{
            'bearer': MeasurementName('http_exchanged_secret'),
          },
        ),
      ],
    );

    expect(
      run.lines.where((String line) => line.contains(credential)),
      isEmpty,
      reason: 'a credential that did not exist when the run started reached a world-readable file',
    );
    expect(
      run.lines.where((String line) => line.contains(Redactor.marker)),
      isNotEmpty,
      reason: 'the value was removed rather than never having reached a recording surface',
    );
  });

  test('THE INNOCENT NEIGHBOUR: published by the kind that declares no credential, it IS in the '
      'record', () async {
    // Same conversation, same network, same echoing answer. What changes is one word in one row —
    // which kind asked for the value — and with it whether anything registered the value at all.
    final ({List<String> lines, ScriptedHttp http, RunRecord record}) run = await runOf(
      <ProgramStep>[exchanging('exchange_http_field'), watching()],
    );

    expect(run.record.exitCode, 0);
    expect(
      run.lines.where((String line) => line.contains(credential)),
      isNotEmpty,
      reason:
          'without this, the test above would pass over a run in which the value never reached the '
          'record, and a clean answer would mean nobody was looking',
    );
  });

  test('the exchange row stands declared, and the run is not fully proven', () async {
    // What the engine says about the row afterwards, through the real step rather than a planted
    // one: nothing re-read the other end, because a second look would be a second exchange.
    final ({List<String> lines, ScriptedHttp http, RunRecord record}) run = await runOf(
      <ProgramStep>[
        exchanging('exchange_http_secret'),
        watching(
          reads: const <String, MeasurementName>{
            'bearer': MeasurementName('http_exchanged_secret'),
          },
        ),
      ],
    );

    expect(run.record.steps.first.verdict, isA<Succeeded>());
    expect(run.record.steps.first.standing, StepStanding.declared);
    expect(run.record.fullyProven, isFalse);
  });

  test(
    'a row filling the bearer from a value nothing declared secret is refused before it runs',
    () {
      // The other half of the rule the record rests on. What hides a credential is the sink
      // registering it where it is published, and only a measurement declared secret is registered —
      // so an argument the step calls secret may take only such a measurement.
      expect(
        () => const ProgramResolver(httpRegistry).resolve(
          Program(
            name: const ProgramName('conversation'),
            roles: const <Role>[],
            steps: <ProgramStep>[
              exchanging('exchange_http_field'),
              watching(
                reads: const <String, MeasurementName>{
                  'bearer': MeasurementName('http_exchanged_field'),
                },
              ),
            ],
          ),
        ),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid failure) => '$failure',
            'message',
            allOf(
              contains('"bearer" is secret while that measurement is not'),
              contains('Declare both or neither'),
            ),
          ),
        ),
      );
    },
  );
}

const RunId _id = RunId('20260817T120000Z-1');

RunRecord _header(FakeClock clock) => RunRecord(
  id: _id,
  program: const ProgramName('conversation'),
  mode: Mode.run,
  argv: const <String>['ansiwise', 'conversation'],
  start: clock.now(),
  stage: const Stage('dev'),
  role: const Role('master'),
  fqdn: const Fqdn('m1.example.com'),
  commit: '0000000',
  fingerprint: 'test-fingerprint',
);
