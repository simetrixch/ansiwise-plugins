import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';
import 'package:test/test.dart';

/// The address an application's tokens are issued at, composed the way this provider composes it.
///
/// **Why it is code rather than a line in a file.** A format string in a program file would build
/// the address there, and a file that can build a string is a file that can compute — then what
/// gets debugged is the file. Deriving it from an answer is not open either: the framework's
/// derivation rules are a closed set that leaves out joining two values on purpose, because a join
/// is where an expression language starts.
///
/// So it is composed here, typed and measured. The one shape this package is allowed to know is the
/// PROVIDER'S own path, the same for every application it stands in front of. Which application,
/// which label and which domain arrive as arguments, and the probes below are written to fail if any
/// of the three were ever fixed in the code.
void main() {
  const StepName under = StepName('measure_issuer_url');

  const MeasureIssuerUrl step = MeasureIssuerUrl(
    subdomain: 'entry',
    domain: SettingsValue(
      what: 'the domain the provider is served on',
      answer: 'domain',
      key: null,
      settingsPath: null,
      runAnswer: null,
    ),
    application: 'subject',
  );

  ({StepContext context, Map<MeasurementName, String> published}) runHolding(
    Map<String, Object> answers,
  ) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{}),
        http: FakeHttp(),
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const _SilentLog(),
        step: under,
        arguments: Arguments.none,
        answers: Arguments(answers),
        facts: Facts.none,
        measurements: _Sink(published),
      ),
      published: published,
    );
  }

  group('the address it publishes', () {
    test('is the provider\'s path, over the label and the domain the row named', () async {
      final ({StepContext context, Map<MeasurementName, String> published}) it = runHolding(
        <String, Object>{'domain': 'one.example.com'},
      );

      expect(await step.check(it.context), isA<Satisfied>());

      expect(
        it.published[const MeasurementName('issuer_url')],
        'https://entry.one.example.com/application/o/subject/',
      );
    });

    test(
      'ends in a slash, because what compares it against a token does not forgive one',
      () async {
        final ({StepContext context, Map<MeasurementName, String> published}) it = runHolding(
          <String, Object>{'domain': 'one.example.com'},
        );
        await step.check(it.context);

        expect(it.published[const MeasurementName('issuer_url')], endsWith('/'));
      },
    );

    test('follows all three parts of the row, and none of them is fixed in the code', () async {
      // THE PLANTED DEFECT this guards: a step that hard-coded any of the three would pass the first
      // probe and this one would still find it.
      const MeasureIssuerUrl other = MeasureIssuerUrl(
        subdomain: 'gate',
        domain: SettingsValue(
          what: 'the domain the provider is served on',
          answer: 'elsewhere',
          key: null,
          settingsPath: null,
          runAnswer: null,
        ),
        application: 'second',
      );
      final ({StepContext context, Map<MeasurementName, String> published}) it = runHolding(
        <String, Object>{'elsewhere': 'two.example.org'},
      );
      await other.check(it.context);

      expect(
        it.published[const MeasurementName('issuer_url')],
        'https://gate.two.example.org/application/o/second/',
      );
    });

    test('is the same on a second run, which is what makes the row repeatable', () async {
      final ({StepContext context, Map<MeasurementName, String> published}) first = runHolding(
        <String, Object>{'domain': 'one.example.com'},
      );
      await step.check(first.context);
      final ({StepContext context, Map<MeasurementName, String> published}) second = runHolding(
        <String, Object>{'domain': 'one.example.com'},
      );
      await step.check(second.context);

      expect(
        second.published[const MeasurementName('issuer_url')],
        first.published[const MeasurementName('issuer_url')],
      );
    });
  });

  group('what it refuses, rather than publishing something wrong', () {
    test('a run holding no such answer', () async {
      // Blocked and not ready: there is nothing this row can do about it, and the refusal names the
      // answer the row pointed at rather than the one somebody meant.
      final ({StepContext context, Map<MeasurementName, String> published}) it = runHolding(
        <String, Object>{'something_else': 'one.example.com'},
      );

      final CheckResult answer = await step.check(it.context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('domain'));
    });

    test('an answer given as nothing', () async {
      // Without this the address would name a host that is a label and a dot, and the refusal for it
      // would come from whatever tried to reach it — a name that resolves nowhere, reported as a
      // network failure rather than as a missing answer.
      final ({StepContext context, Map<MeasurementName, String> published}) it = runHolding(
        <String, Object>{'domain': ''},
      );

      expect(await step.check(it.context), isA<Blocked>());
    });
  });
}

/// A log nothing reads, so a probe measures what a step DID and not what it said about it.
final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// Collects what a step publishes, so a probe can read it.
final class _Sink implements MeasurementSink {
  const _Sink(this._into);

  final Map<MeasurementName, String> _into;

  @override
  void publish(MeasurementName name, String value) => _into[name] = value;
}
