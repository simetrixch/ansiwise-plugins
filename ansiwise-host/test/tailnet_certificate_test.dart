import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The address in the serving certificate, and the two silent failures the step is built around: a
/// template edit the re-sign never carried into the request on disk, and a stale address left
/// naming a machine that no longer holds it.
void main() {
  const String template = '/etc/signer/request.template';
  const String certificate = '/etc/signer/server.crt';
  const String readCert = 'openssl x509 -in $certificate -noout -text';

  const StampTailnetAddressInCertificate step = StampTailnetAddressInCertificate(
    template: template,
    certificate: certificate,
    marker: '#MORENAMES',
    addressRange: '100.64.0.0/10',
    resign: <String>['signer', 'refresh'],
    settledBy: <String>['signer', 'ready'],
    waitSeconds: 600,
    elevated: true,
  );

  /// A template in the request format: some names, then the marker that ends the section.
  const String bareTemplate = '[ alt_names ]\nIP.1 = 10.0.0.5\n#MORENAMES\n';

  StepContext contextOn(FakeShell shell, FakeFiles files) => StepContext(
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

  FakeShell holding(String address) => FakeShell()
    ..answers(
      'tailscale status --json',
      '{"BackendState":"Running","Self":{"TailscaleIPs":["$address"]}}',
    );

  test('a machine with no address on the network is blocked — nothing to certify', () async {
    final FakeShell shell = FakeShell()
      ..answers('tailscale status --json', '{"BackendState":"NeedsLogin"}');
    expect(
      await step.check(contextOn(shell, FakeFiles(<String, String>{template: bareTemplate}))),
      isA<Blocked>(),
    );
  });

  test('a template without the marker is blocked — a name after it is never read', () async {
    final FakeFiles files = FakeFiles(<String, String>{
      template: '[ alt_names ]\nIP.1 = 10.0.0.5\n',
    });
    expect(await step.check(contextOn(holding('100.64.0.7'), files)), isA<Blocked>());
  });

  test(
    'the address lands in FRONT of the marker, the machine\'s own interfaces untouched',
    () async {
      final FakeShell shell = holding('100.64.0.7');
      final FakeFiles files = FakeFiles(<String, String>{template: bareTemplate});
      shell.changes('signer refresh', () {
        shell.answers(readCert, 'IP Address:10.0.0.5, IP Address:100.64.0.7\n');
      });
      final StepContext context = contextOn(shell, files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(
        files.contents[template],
        '[ alt_names ]\nIP.1 = 10.0.0.5\nIP.2 = 100.64.0.7\n#MORENAMES\n',
      );
      expect(shell.ran, contains('signer refresh'));
      expect(shell.ran, contains('signer ready'));
      expect(await step.check(context), isA<Satisfied>());
    },
  );

  test(
    'a STALE network address is removed — it may already name somebody else\'s machine',
    () async {
      // The planted defect: the machine rejoined and was handed .7, and the template still says .3 —
      // an address the coordinator is free to hand to a different machine, whose identity this
      // machine would then satisfy in a verified handshake.
      final FakeShell shell = holding('100.64.0.7');
      final FakeFiles files = FakeFiles(<String, String>{
        template: '[ alt_names ]\nIP.1 = 10.0.0.5\nIP.2 = 100.64.0.3\n#MORENAMES\n',
      });
      shell.changes('signer refresh', () {
        shell.answers(readCert, 'IP Address:10.0.0.5, IP Address:100.64.0.7\n');
      });
      final StepContext context = contextOn(shell, files);

      await step.apply(context);

      expect(files.contents[template], isNot(contains('100.64.0.3')));
      expect(files.contents[template], contains('IP.3 = 100.64.0.7'));
    },
  );

  test(
    'a certificate that already names the address STILL re-signs on a changed template',
    () async {
      // The silent failure this exists for: the renderer listed the address off the live interface,
      // so the certificate carries it — but the template edit is not in the request on disk, and the
      // distribution's watcher tears the node down over that difference moments after a step that
      // skipped the re-sign reported success.
      final FakeShell shell = holding('100.64.0.7')
        ..answers(readCert, 'IP Address:10.0.0.5, IP Address:100.64.0.7\n');
      final FakeFiles files = FakeFiles(<String, String>{template: bareTemplate});
      final StepContext context = contextOn(shell, files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(shell.ran, contains('signer refresh'));
    },
  );

  test(
    'a template already right and a certificate already naming the address: nothing to do',
    () async {
      final FakeShell shell = holding('100.64.0.7')
        ..answers(readCert, 'IP Address:10.0.0.5, IP Address:100.64.0.7\n');
      final FakeFiles files = FakeFiles(<String, String>{
        template: '[ alt_names ]\nIP.1 = 10.0.0.5\nIP.2 = 100.64.0.7\n#MORENAMES\n',
      });
      expect(await step.check(contextOn(shell, files)), isA<Satisfied>());
      expect(shell.ran.where((String c) => c == 'signer refresh'), isEmpty);
    },
  );

  test('the name is matched WHOLE — .7 does not pass on a certificate carrying .71', () async {
    final FakeShell shell = holding('100.64.0.7')..answers(readCert, 'IP Address:100.64.0.71\n');
    final FakeFiles files = FakeFiles(<String, String>{
      template: '[ alt_names ]\nIP.2 = 100.64.0.7\n#MORENAMES\n',
    });
    expect(await step.check(contextOn(shell, files)), isA<Ready>());
  });

  test(
    'the range is compared as NUMBERS — 100.127.x.x is inside, 100.128.x.x is outside',
    () async {
      // 100.64.0.0/10 spans second octets 64 through 127, which no leading-substring match gets
      // right. A stale 100.127 address goes; a 100.128 one is somebody's real interface and stays.
      final FakeShell shell = holding('100.64.0.7');
      final FakeFiles files = FakeFiles(<String, String>{
        template: '[ alt_names ]\nIP.1 = 100.127.0.9\nIP.2 = 100.128.0.9\n#MORENAMES\n',
      });
      shell.changes('signer refresh', () {
        shell.answers(readCert, 'IP Address:100.64.0.7\n');
      });
      final StepContext context = contextOn(shell, files);

      await step.apply(context);

      expect(files.contents[template], isNot(contains('100.127.0.9')));
      expect(files.contents[template], contains('100.128.0.9'));
    },
  );

  test('a re-sign that fails throws rather than reporting a certificate nobody signed', () async {
    final FakeShell shell = holding('100.64.0.7')..fails('signer refresh', stderr: 'no backup');
    final FakeFiles files = FakeFiles(<String, String>{template: bareTemplate});
    await expectLater(step.apply(contextOn(shell, files)), throwsA(isA<CommandFailed>()));
  });

  test('a machine that does not come back to serving fails HERE, not three steps later', () async {
    // The settling command is the caller's next act brought forward: a node still restarting fails
    // everything dialled at it with an error about the dialler's own command instead of about the
    // re-sign still in progress.
    final FakeShell shell = holding('100.64.0.7')..fails('signer ready', stderr: 'not ready');
    shell.changes('signer refresh', () {
      shell.answers(readCert, 'IP Address:100.64.0.7\n');
    });
    final FakeFiles files = FakeFiles(<String, String>{template: bareTemplate});
    await expectLater(step.apply(contextOn(shell, files)), throwsA(isA<CommandFailed>()));
  });

  test(
    'taking it back restores the template and re-signs, so request and certificate agree',
    () async {
      final FakeShell shell = holding('100.64.0.7');
      shell.changes('signer refresh', () {
        shell.answers(readCert, 'IP Address:100.64.0.7\n');
      });
      final FakeFiles files = FakeFiles(<String, String>{template: bareTemplate});
      final StepContext context = contextOn(shell, files);

      final String? before = await step.capture(context);
      await step.apply(context);
      await step.undo(context, before);

      expect(files.contents[template], bareTemplate);
      expect(shell.ran.where((String c) => c == 'signer refresh').length, 2);
    },
  );
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
