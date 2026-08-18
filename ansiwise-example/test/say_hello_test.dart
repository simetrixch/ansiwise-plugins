import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_example/ansiwise_example.dart';
import 'package:test/test.dart';
import 'package:ansiwise_core/testing.dart';

void main() {
  test('SayHello parses its subject', () {
    final SayHello step = SayHello.fromArguments(
      const Arguments(<String, Object>{'subject': 'World'}),
    );
    expect(step.subject, 'World');
  });

  test('SayHello check is always Satisfied', () async {
    const SayHello step = SayHello(subject: 'Test');
    final StepContext context = StepContext(
      shell: FakeShell(),
      files: FakeFiles(<String, String>{}),
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const _SilentLog(),
      step: const StepName('under_test'),
      arguments: Arguments.none,
      answers: Arguments.none,
      facts: Facts.none,
    );
    final CheckResult check = await step.check(context);
    expect(check, isA<Satisfied>());
  });
}

class _SilentLog implements Logger {
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
