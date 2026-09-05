import 'package:ansiwise_authentik/ansiwise_authentik.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The domain read off a settings file of the machine instead of copied into an answer.
///
/// One step of the three drives it here, because all three take the value the same way: they build
/// one [SettingsValue] from the same four arguments and ask it. What is measured is that a reading
/// which cannot be taken is a sentence naming the file and the key, and never a domain of nothing —
/// an empty one composes an address that is a label and a slash, and the row would report itself
/// green against it.
void main() {
  const StepName under = StepName('measure_issuer_url');
  const String settingsPath = 'clusters/active/<fqdn>.yaml';
  const String settingsHere = 'clusters/active/one.example.com.yaml';

  const String settings =
      'global:\n'
      '  domain: one.example.com\n'
      '  empty:\n'
      '  labels:\n'
      '    - entry\n';

  MeasureIssuerUrl reading({
    String key = 'global.domain',
    String? answer,
    String path = settingsPath,
  }) => MeasureIssuerUrl(
    subdomain: 'entry',
    domain: SettingsValue(
      what: 'the domain the provider is served on',
      answer: answer,
      key: key,
      settingsPath: path,
      runAnswer: 'fqdn',
    ),
    application: 'subject',
  );

  ({StepContext context, List<String> said}) machineWith(
    String? text, {
    Map<String, Object> answers = const <String, Object>{'fqdn': 'one.example.com'},
  }) {
    final List<String> said = <String>[];
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{if (text case final String held) settingsHere: held}),
        http: FakeHttp(),
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: _CollectingLog(said),
        step: under,
        arguments: Arguments.none,
        answers: Arguments(answers),
        facts: Facts.none,
        measurements: const _NoSink(),
      ),
      said: said,
    );
  }

  test('THE INNOCENT CASE: the domain is read off the file and the slot is filled', () async {
    final CheckResult result = await reading().check(machineWith(settings).context);

    expect(result, isA<Satisfied>());
    expect((result as Satisfied).because, contains('https://entry.one.example.com/'));
  });

  test('a key the file does not carry is refused, and the sentence names both', () async {
    final CheckResult result = await reading(
      key: 'global.hostname',
    ).check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect(
      (result as Blocked).reason,
      allOf(contains(settingsHere), contains('global.hostname')),
      reason: 'an operator correcting a key needs the file and the key in one sentence',
    );
  });

  test('a key holding nothing is refused rather than composing a label and a slash', () async {
    final CheckResult result = await reading(
      key: 'global.empty',
    ).check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('nothing at all'));
  });

  test('a key holding a list is refused', () async {
    final CheckResult result = await reading(
      key: 'global.labels',
    ).check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('list or a map'));
  });

  test('a file that is not on this machine is refused, by the filled path', () async {
    final CheckResult result = await reading().check(machineWith(null).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains(settingsHere));
  });

  test('a file that is not YAML is refused', () async {
    final CheckResult result = await reading().check(
      machineWith('global:\n  domain: "unterminated\n').context,
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('YAML'));
  });

  test('a path whose slot nothing fills is refused rather than read as written', () async {
    final CheckResult result = await reading().check(
      machineWith(settings, answers: const <String, Object>{}).context,
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('<fqdn>'));
  });

  test('a value named by neither an answer nor a key is refused', () async {
    const MeasureIssuerUrl step = MeasureIssuerUrl(
      subdomain: 'entry',
      domain: SettingsValue(
        what: 'the domain the provider is served on',
        answer: null,
        key: null,
        settingsPath: null,
        runAnswer: null,
      ),
      application: 'subject',
    );

    final CheckResult result = await step.check(machineWith(settings).context);

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('neither an answer nor a key'));
  });

  test('a row naming both reads the ANSWER, and says which key it did not read', () async {
    final ({StepContext context, List<String> said}) machine = machineWith(
      settings,
      answers: const <String, Object>{'fqdn': 'one.example.com', 'served': 'other.example.org'},
    );

    final CheckResult result = await reading(answer: 'served').check(machine.context);

    expect(result, isA<Satisfied>());
    expect(
      (result as Satisfied).because,
      contains('https://entry.other.example.org/'),
      reason: 'what this run was told beats what a file records',
    );
    expect(
      machine.said.join('\n'),
      allOf(contains('served'), contains('global.domain')),
      reason: 'a stale answer beside a live key has to be visible in the record',
    );
  });
}

final class _CollectingLog implements Logger {
  const _CollectingLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}

final class _NoSink implements MeasurementSink {
  const _NoSink();

  @override
  void publish(MeasurementName name, String value) {}
}
