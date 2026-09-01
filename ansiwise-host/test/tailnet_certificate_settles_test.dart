import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// Waiting for what the re-sign restarted, and the failure that made this necessary.
///
/// THE PLANTED CASE IS THE ONE THAT HAPPENED. Measured on apps6 on 2026-09-01: this step re-signed
/// the serving certificate, its settling command reported success, and twenty-five seconds later the
/// next program was refused by an API server that had not finished restarting — `the connection to
/// the server 127.0.0.1:16443 was refused`. A command asked ONCE can only report the instant it was
/// asked in, and the instant after a re-sign is the one in which what serves is still coming back.
void main() {
  const String template = '/etc/signer/request.template';
  const String certificate = '/etc/signer/server.crt';
  const String readCert = 'openssl x509 -in $certificate -noout -text';
  const String address = '100.64.0.2';

  const StampTailnetAddressInCertificate step = StampTailnetAddressInCertificate(
    template: template,
    certificate: certificate,
    marker: '#MORENAMES',
    addressRange: '100.64.0.0/10',
    resign: <String>['signer', 'refresh'],
    settledBy: <String>['signer', 'ready'],
    // Small on purpose: the wait asks every three seconds, so this is four askings.
    waitSeconds: 12,
    elevated: true,
  );

  const String bareTemplate = '[ alt_names ]\nIP.1 = 10.0.0.5\n#MORENAMES\n';

  StepContext contextOn(Shell shell, FakeFiles files) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('stamp_tailnet_address_in_certificate'),
    arguments: Arguments.none,
    facts: Facts.none,
  );

  FakeFiles carrying() => FakeFiles(<String, String>{template: bareTemplate});

  _ComingBack shell({required int refusalsBeforeItServes}) => _ComingBack(
    refusals: refusalsBeforeItServes,
    inner: FakeShell()
      ..answers(
        'tailscale status --json',
        '{"BackendState":"Running","Self":{"TailscaleIPs":["$address"]}}',
      )
      ..answers(readCert, 'X509v3 Subject Alternative Name:\n  IP Address:$address\n'),
  );

  test('THE PLANTED CASE: it keeps asking while the thing is still coming back', () async {
    final _ComingBack coming = shell(refusalsBeforeItServes: 3);

    await step.apply(contextOn(coming, carrying()));

    expect(
      coming.asked,
      4,
      reason: 'three refusals and then the answer — asking once would have failed on the first',
    );
  });

  test('THE INNOCENT CASE: one that serves straight away is asked exactly once', () async {
    final _ComingBack coming = shell(refusalsBeforeItServes: 0);

    await step.apply(contextOn(coming, carrying()));

    expect(coming.asked, 1, reason: 'a wait must not cost time where there is nothing to wait for');
  });

  test('one that never comes back is SAID, with what was asked and for how long', () async {
    final _ComingBack coming = shell(refusalsBeforeItServes: 99);

    await expectLater(
      step.apply(contextOn(coming, carrying())),
      throwsA(
        isA<CommandFailed>().having(
          (CommandFailed e) => e.toString(),
          'names the wait and what it means',
          allOf(contains('12s'), contains('not serving again')),
        ),
      ),
    );
  });
}

/// A machine whose settling command refuses [refusals] times and answers afterwards.
final class _ComingBack implements Shell {
  _ComingBack({required this.refusals, required this.inner});

  final int refusals;
  final FakeShell inner;

  /// How often the settling command was asked.
  int asked = 0;

  @override
  Future<CommandResult> run(Command command) async {
    if (command.argv.join(' ') == 'signer ready') {
      asked++;
      return asked > refusals
          ? const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero)
          : const CommandResult(
              exitCode: 1,
              stdout: '',
              stderr: 'the connection to the server 127.0.0.1:16443 was refused',
              elapsed: Duration.zero,
            );
    }
    return inner.run(command);
  }
}

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
