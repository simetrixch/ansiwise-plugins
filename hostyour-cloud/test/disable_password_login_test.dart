import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// Closing the password door, and the silent failure that makes it dangerous.
///
/// A drop-in written into a directory nothing includes changes nothing, and sshd says not one word
/// about ignoring it — the password simply keeps working. Every test here is about that silence
/// being turned into a failure.
void main() {
  const String dropIn = '/etc/ssh/sshd_config.d/50-hostyour-cloud.conf';
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
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
      final FakeFiles files = FakeFiles(<String, String>{dropIn: DisablePasswordLogin.content});

      await step.undo(contextOn(shell, files));

      expect(files.deleted, <String>[dropIn]);
      expect(shell.ran, contains('systemctl reload ssh'));
    },
  );

  test('the program proves the key works before it takes the password away', () {
    final Program program = loadProgram(
      File('programs/disable-password-login.yaml').readAsStringSync(),
      where: 'disable-password-login.yaml',
    );
    final List<StepName> order = <StepName>[for (final ProgramStep s in program.steps) s.step];

    expect(
      order.indexOf(const StepName('require_key_login_possible')),
      lessThan(order.indexOf(const StepName('disable_password_login'))),
      reason: 'taking the password away before the key is proven locks the operator out',
    );
    expect(
      program.steps.every((ProgramStep s) => s.onFailure == OnFailure.die),
      isTrue,
      reason: 'nothing in this program may be carried past as a warning',
    );
  });

  test('deploy-host does NOT take the password away', () {
    // The machine cannot prove the operator's key login works, because the private half never comes
    // here. So the two are two programs, and this is what keeps them apart.
    final Program deployHost = loadProgram(
      File('programs/deploy-host.yaml').readAsStringSync(),
      where: 'deploy-host.yaml',
    );
    expect(
      deployHost.steps.map((ProgramStep s) => s.step),
      isNot(contains(const StepName('disable_password_login'))),
    );
  });
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
