import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// Closing the password door, and the silent failure that makes it dangerous.
///
/// A drop-in written into a directory nothing includes changes nothing, and sshd says not one word
/// about ignoring it — the password simply keeps working. Every test here is about that silence
/// being turned into a failure.
void main() {
  /// Where the drop-in goes, as a program row would name it. Which file it is is the product's to
  /// choose, so the step is told rather than knowing.
  const String dropIn = '/etc/ssh/sshd_config.d/50-no-password.conf';
  const DisablePasswordLogin step = DisablePasswordLogin(
    dropIn: dropIn,
    reload: <String>['systemctl', 'reload', 'ssh'],
  );

  /// An sshd that answers [password] for both password settings.
  String reported(String password) =>
      'port 22\n'
      'pubkeyauthentication yes\n'
      'passwordauthentication $password\n'
      'kbdinteractiveauthentication $password\n';

  StepContext contextOn(FakeShell shell, FakeFiles files) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('disable_password_login'),
    arguments: Arguments.none,
    facts: Facts.none,
  );

  test('a machine that already refuses a password has nothing to do', () async {
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
    final CheckResult answer = await step.check(contextOn(shell, FakeFiles()));
    expect(answer, isA<Satisfied>());
  });

  test('a machine that still accepts one is ready', () async {
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
    expect(await step.check(contextOn(shell, FakeFiles())), isA<Ready>());
  });

  test('applying writes the drop-in and reloads sshd', () async {
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
    final FakeFiles files = FakeFiles();
    await step.apply(contextOn(shell, files));

    expect(files.written, <String>[dropIn]);
    expect(files.contents[dropIn], contains('PasswordAuthentication no'));
    expect(files.contents[dropIn], contains('KbdInteractiveAuthentication no'));
    expect(shell.ran, contains('systemctl reload ssh'));
  });

  test('a drop-in nothing reads is a FAILURE, not a success', () async {
    // The whole reason the verdict comes from `sshd -T` rather than from the file: a directory that
    // is not included leaves the file on disk, the reload returning zero, and the password still
    // working. Everything looks done and nothing is.
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
    final FakeFiles files = FakeFiles();

    await step.apply(contextOn(shell, files));
    final CheckResult after = await step.check(contextOn(shell, files));

    expect(
      after,
      isNot(isA<Satisfied>()),
      reason: 'the file was written and sshd still accepts a password',
    );
  });

  test('a reload that fails throws rather than reporting success', () async {
    final FakeShell shell = FakeShell()
      ..answers('sshd -T', reported('yes'))
      ..fails('systemctl reload ssh', stderr: 'Job failed');
    await expectLater(step.apply(contextOn(shell, FakeFiles())), throwsA(isA<CommandFailed>()));
  });

  test(
    'taking it back removes the file and reloads, so sshd stops holding the old setting',
    () async {
      // A machine that carried no drop-in, so the capture reads nothing and the undo removes what
      // this run put there. The whole sequence is driven rather than the undo alone, because what
      // the undo does is decided by what the capture read before the apply.
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
      final FakeFiles files = FakeFiles();
      final StepContext context = contextOn(shell, files);

      final String? before = await step.capture(context);
      await step.apply(context);
      await step.undo(context, before);

      expect(files.deleted, <String>[dropIn]);
      expect(shell.ran, contains('systemctl reload ssh'));
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
