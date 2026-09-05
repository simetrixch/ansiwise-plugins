import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The password door in both directions, and the silent failure that makes it dangerous.
///
/// A drop-in written into a directory nothing includes changes nothing, and sshd says not one word
/// about ignoring it — the password simply keeps working, or keeps being refused. Every test here is
/// about that silence being turned into a failure, and both directions are held to it.
void main() {
  /// Where the drop-in goes, as a program row would name it. Which file it is is the product's to
  /// choose, so the step is told rather than knowing.
  const String dropIn = '/etc/ssh/sshd_config.d/50-password.conf';
  const List<String> reload = <String>['systemctl', 'reload', 'ssh'];

  const PasswordLogin closing = PasswordLogin(dropIn: dropIn, reload: reload, allowed: false);
  const PasswordLogin opening = PasswordLogin(dropIn: dropIn, reload: reload, allowed: true);

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
    step: const StepName('password_login'),
    arguments: Arguments.none,
    facts: Facts.none,
  );

  group('closing the door', () {
    test('a machine that already refuses a password has nothing to do', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
      expect(await closing.check(contextOn(shell, FakeFiles())), isA<Satisfied>());
    });

    test('a machine that still accepts one is ready', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
      expect(await closing.check(contextOn(shell, FakeFiles())), isA<Ready>());
    });

    test('applying writes the drop-in and reloads sshd', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
      final FakeFiles files = FakeFiles();
      await closing.apply(contextOn(shell, files));

      expect(files.written, <String>[dropIn]);
      expect(files.contents[dropIn], contains('PasswordAuthentication no'));
      expect(files.contents[dropIn], contains('KbdInteractiveAuthentication no'));
      expect(shell.ran, contains('systemctl reload ssh'));
    });
  });

  group('opening it again', () {
    test('a machine that already accepts a password has nothing to do', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
      expect(await opening.check(contextOn(shell, FakeFiles())), isA<Satisfied>());
    });

    test('a machine that refuses one is ready', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
      expect(await opening.check(contextOn(shell, FakeFiles())), isA<Ready>());
    });

    test('applying writes the SAME file the closing direction writes', () async {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('no'));
      final FakeFiles files = FakeFiles();
      await opening.apply(contextOn(shell, files));

      expect(files.written, <String>[
        dropIn,
      ], reason: 'the two directions own one file, so one undoes the other exactly');
      expect(files.contents[dropIn], contains('PasswordAuthentication yes'));
      expect(files.contents[dropIn], contains('KbdInteractiveAuthentication yes'));
      expect(shell.ran, contains('systemctl reload ssh'));
    });

    test('both settings move together, so a door that reads as open really is', () async {
      // A machine whose keyboard-interactive door is closed takes no password whatever
      // PasswordAuthentication says, so the check is not satisfied until both stand.
      final FakeShell shell = FakeShell()
        ..answers(
          'sshd -T',
          'port 22\npasswordauthentication yes\nkbdinteractiveauthentication no\n',
        );

      expect(await opening.check(contextOn(shell, FakeFiles())), isA<Ready>());
    });
  });

  group('driven twice, in each direction', () {
    /// A fake sshd that reports what the drop-in last written says, which is what a real one does
    /// once the reload has run.
    FakeShell following(FakeFiles files) {
      final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
      shell.changes(
        'systemctl reload ssh',
        () => shell.answers(
          'sshd -T',
          reported(
            (files.contents[dropIn] ?? '').contains('PasswordAuthentication no') ? 'no' : 'yes',
          ),
        ),
      );
      return shell;
    }

    for (final (String name, PasswordLogin step) in <(String, PasswordLogin)>[
      ('closing', closing),
      ('opening', opening),
    ]) {
      test('$name a second time reports there is nothing to do', () async {
        final FakeFiles files = FakeFiles();
        final FakeShell shell = following(files);
        final StepContext context = contextOn(shell, files);

        await step.apply(context);
        files.written.clear();

        expect(await step.check(context), isA<Satisfied>());
        expect(files.written, isEmpty);
      });
    }
  });

  test('the opening direction takes the closing one back exactly', () async {
    final FakeFiles files = FakeFiles();
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
    final StepContext context = contextOn(shell, files);

    await closing.apply(context);
    final String closed = files.contents[dropIn]!;
    await opening.apply(context);
    final String opened = files.contents[dropIn]!;

    expect(closed, isNot(opened));
    expect(opened, contains('PasswordAuthentication yes'));
    expect(closed, contains('PasswordAuthentication no'));
  });

  test('a drop-in nothing reads is a FAILURE, not a success', () async {
    // The whole reason the verdict comes from `sshd -T` rather than from the file: a directory that
    // is not included leaves the file on disk, the reload returning zero, and the password still
    // working. Everything looks done and nothing is.
    final FakeShell shell = FakeShell()..answers('sshd -T', reported('yes'));
    final FakeFiles files = FakeFiles();

    await closing.apply(contextOn(shell, files));

    expect(
      await closing.check(contextOn(shell, files)),
      isNot(isA<Satisfied>()),
      reason: 'the file was written and sshd still accepts a password',
    );
  });

  test('sshd that cannot report its configuration blocks BOTH directions', () async {
    final FakeShell shell = FakeShell()..fails('sshd -T', stderr: 'must be run as root');

    for (final PasswordLogin step in <PasswordLogin>[closing, opening]) {
      expect(await step.check(contextOn(shell, FakeFiles())), isA<Blocked>());
    }
  });

  test('a reload that fails throws rather than reporting success', () async {
    final FakeShell shell = FakeShell()
      ..answers('sshd -T', reported('yes'))
      ..fails('systemctl reload ssh', stderr: 'Job failed');
    await expectLater(closing.apply(contextOn(shell, FakeFiles())), throwsA(isA<CommandFailed>()));
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

      final String? before = await closing.capture(context);
      await closing.apply(context);
      await closing.undo(context, before);

      expect(files.deleted, <String>[dropIn]);
      expect(shell.ran, contains('systemctl reload ssh'));
    },
  );

  test('both names are registered, and both build the one class', () {
    for (final String name in <String>['disable_password_login', 'enable_password_login']) {
      final RegisteredStep? entry = hostRegistry.step(StepName(name));
      expect(entry, isNotNull, reason: '$name is what a program row writes');
      expect(entry!.source, 'lib/src/steps/host/password_login.dart:38');
    }

    expect(
      hostSteps[const StepName('disable_password_login')]!.create(
        const Arguments(<String, Object>{'drop_in': dropIn, 'reload': reload}),
      ),
      isA<PasswordLogin>().having((PasswordLogin it) => it.allowed, 'allowed', isFalse),
    );
    expect(
      hostSteps[const StepName('enable_password_login')]!.create(
        const Arguments(<String, Object>{'drop_in': dropIn, 'reload': reload}),
      ),
      isA<PasswordLogin>().having((PasswordLogin it) => it.allowed, 'allowed', isTrue),
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
