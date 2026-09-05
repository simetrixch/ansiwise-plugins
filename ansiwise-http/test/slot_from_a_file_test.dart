import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_http/ansiwise_http.dart';
import 'package:test/test.dart';

import 'scripted_http.dart';

/// A slot of a waiting row filled from a key of a settings file instead of from an answer.
///
/// The address a row asks is what this decides. A slot filled from a COPY of a value is a request
/// that reaches the wrong machine and answers perfectly, so a value an installation already wrote
/// down is read where it stands. Every way that reading can fail is a refusal naming the file and
/// the key, and never an empty slot.
void main() {
  const StepName under = StepName('wait_for_http_field');
  const String settingsPath = 'clusters/active/<fqdn>.yaml';
  const String settingsHere = 'clusters/active/one.example.com.yaml';

  const String settings =
      'global:\n'
      '  endpoints:\n'
      '    store:\n'
      '      host: store.example.com\n'
      '      empty:\n'
      '      names:\n'
      '        - one\n';

  WaitForHttpField waiting({
    String key = 'global.endpoints.store.host',
    String file = settingsPath,
  }) => WaitForHttpField.fromArguments(
    Arguments(<String, Object>{
      'waiting_for': 'the store to answer',
      'url': 'https://<store>/v1/state',
      'field': 'state',
      'until': <String>['ready'],
      'timeout_seconds': 1,
      'interval_seconds': 1,
      'values': <String, Object?>{
        'store': <String, Object?>{'file': file, 'key': key, 'run_answer': 'fqdn'},
      },
    }),
  );

  ({StepContext context, FakeHttp http}) machineWith(
    String? text, {
    Map<String, Object> answers = const <String, Object>{'fqdn': 'one.example.com'},
  }) {
    final FakeHttp http = FakeHttp();
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{if (text case final String held) settingsHere: held}),
        http: http,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const NothingSaid(),
        step: under,
        arguments: Arguments.none,
        answers: Arguments(answers),
        facts: Facts.none,
      ),
      http: http,
    );
  }

  test('THE INNOCENT CASE: the address is composed from the key, and the ask goes there', () async {
    final ({StepContext context, FakeHttp http}) machine = machineWith(settings);
    machine.http.answers('GET https://store.example.com/v1/state', body: '{"state":"ready"}');

    final CheckResult result = await waiting().check(machine.context);

    expect(result, isA<Satisfied>());
    expect(machine.http.sent, contains('GET https://store.example.com/v1/state'));
  });

  test('a key the file does not carry is refused, and the sentence names both', () async {
    final ({StepContext context, FakeHttp http}) machine = machineWith(settings);
    final CheckResult result = await waiting(
      key: 'global.endpoints.store.address',
    ).check(machine.context);

    expect(result, isA<Blocked>());
    expect(
      (result as Blocked).reason,
      allOf(contains(settingsHere), contains('global.endpoints.store.address')),
    );
    expect(machine.http.sent, isEmpty, reason: 'nothing is asked of an address nobody composed');
  });

  test('a key holding nothing is refused rather than asking a bare scheme', () async {
    final CheckResult result = await waiting(
      key: 'global.endpoints.store.empty',
    ).check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('nothing at all'));
  });

  test('a key holding a list is refused', () async {
    final CheckResult result = await waiting(
      key: 'global.endpoints.store.names',
    ).check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('list or a map'));
  });

  test('a file that is not on the machine is refused, by the filled path', () async {
    final CheckResult result = await waiting().check(machineWith(null).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains(settingsHere));
  });

  test('a file that is not YAML is refused', () async {
    final CheckResult result = await waiting().check(
      machineWith('global:\n  endpoints:\n   x: "unterminated\n').context,
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('YAML'));
  });

  test('a path whose slot nothing fills is refused rather than read as written', () async {
    final CheckResult result = await waiting().check(
      machineWith(settings, answers: const <String, Object>{}).context,
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('<fqdn>'));
  });

  group('what a row may write', () {
    test('THE INNOCENT NEIGHBOUR: an answer source is still read', () {
      expect(
        slotSources(<String, Object?>{
          'store': <String, Object?>{'answer': 'store_host'},
        })['store'],
        isA<SlotAnswer>(),
      );
    });

    test('a file source carries its key and the answer that fills its slot', () {
      final SlotSource? source = slotSources(<String, Object?>{
        'store': <String, Object?>{
          'file': settingsPath,
          'key': 'global.endpoints.store.host',
          'run_answer': 'fqdn',
        },
      })['store'];

      expect(source, isA<SlotFile>());
      expect((source! as SlotFile).key, 'global.endpoints.store.host');
      expect((source as SlotFile).runAnswer, 'fqdn');
    });

    test('a file with no key is refused where the row is read', () {
      expect(
        () => slotSources(<String, Object?>{
          'store': <String, Object?>{'file': settingsPath},
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
