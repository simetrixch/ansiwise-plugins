import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

/// The client's four membership acts, and the silences each is built to refuse: a `down` that
/// leaves the client Running, a bare `up` that comes back with nothing, a logout that keeps the
/// node key, and a join onto somebody else's network.
void main() {
  StepContext contextOn(
    FakeShell shell, {
    FakeFiles? files,
    Map<String, Object> answers = const <String, Object>{},
  }) => StepContext(
    shell: shell,
    files: files ?? FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('tailnet'),
    arguments: Arguments.none,
    answers: Arguments(answers),
    facts: Facts.none,
  );

  FakeShell clientReporting(String state) =>
      FakeShell()..answers('tailscale status --json', '{"BackendState":"$state"}');

  group('tailnet_leave', () {
    const TailnetLeave step = TailnetLeave();

    test('a machine already off the network has nothing to do', () async {
      expect(await step.check(contextOn(clientReporting('Stopped'))), isA<Satisfied>());
    });

    test('a client that cannot be read BLOCKS rather than guessing', () async {
      // The planted silence: no client, no daemon — status answers nothing. Guessing "off" here
      // would report a leave done on a machine nobody read.
      final FakeShell shell = FakeShell()..fails('tailscale status --json');
      expect(await step.check(contextOn(shell)), isA<Blocked>());
    });

    test('a down that leaves the client Running is a FAILURE, not a success', () async {
      // The exit code says done, the state says otherwise — and the state wins, because everything
      // keeps dialling a machine whose leave was reported on the exit code alone.
      final FakeShell shell = clientReporting('Running');
      final StepContext context = contextOn(shell);
      await step.apply(context);
      expect(await step.check(context), isNot(isA<Satisfied>()));
    });

    test('applying takes the machine off, and the second run has nothing to do', () async {
      final FakeShell shell = clientReporting('Running');
      shell.changes('tailscale down', () {
        shell.answers('tailscale status --json', '{"BackendState":"Stopped"}');
      });
      final StepContext context = contextOn(shell);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('taking it back brings the membership up only where it was up before', () async {
      final FakeShell shell = clientReporting('Running');
      final StepContext context = contextOn(shell);
      final bool wasOn = await step.capture(context);
      await step.apply(context);
      await step.undo(context, wasOn);
      expect(shell.ran, contains('tailscale up'));
    });
  });

  group('tailnet_reconnect', () {
    const TailnetReconnect step = TailnetReconnect(waitSeconds: 60);

    test('a machine already on the network has nothing to do', () async {
      expect(await step.check(contextOn(clientReporting('Running'))), isA<Satisfied>());
    });

    test('the up is BARE — one flag would make the client refuse every machine here', () async {
      final FakeShell shell = clientReporting('Stopped');
      shell.changes('tailscale up', () {
        shell.answers('tailscale status --json', '{"BackendState":"Running"}');
      });
      await step.apply(contextOn(shell));
      expect(shell.ran, contains('tailscale up'));
    });

    test('a client that comes back holding nothing is a FAILURE that says so', () async {
      // The planted defect: the client has no usable credential, prints a login address for a
      // person this run does not have, and is cut short still logged out. Reporting the exit code
      // would call that success.
      final FakeShell shell = clientReporting('NeedsLogin');
      await expectLater(step.apply(contextOn(shell)), throwsA(isA<StateError>()));
    });
  });

  group('tailnet_logout', () {
    const TailnetLogout step = TailnetLogout();

    test('a client that already holds no key has nothing to do', () async {
      expect(await step.check(contextOn(clientReporting('NeedsLogin'))), isA<Satisfied>());
    });

    test('a client that is merely DOWN still holds its key, so there is work', () async {
      // The distinction the rejoin stands on: down keeps the node key and the join would be
      // skipped as "already on the network"; only the logout makes the next join real.
      expect(await step.check(contextOn(clientReporting('Stopped'))), isA<Ready>());
    });

    test('a logout that keeps the client Running is a FAILURE, not a success', () async {
      final FakeShell shell = clientReporting('Running');
      final StepContext context = contextOn(shell);
      await step.apply(context);
      expect(await step.check(context), isNot(isA<Satisfied>()));
    });
  });

  group('tailnet_join', () {
    const TailnetJoin step = TailnetJoin(
      stagedKeyPath: '/tmp/staged-key',
      acceptDns: false,
      waitSeconds: 180,
    );
    const Map<String, Object> answers = <String, Object>{
      'login_server': 'https://net.example/',
      'auth_key': ' k-join\n',
    };
    const String up =
        'tailscale up --login-server https://net.example '
        '--auth-key file:/tmp/staged-key --accept-dns=false';

    test('already on OUR network has nothing to do, trailing slash and all', () async {
      // The two spellings of one coordinator address compare equal, or every rerun would try to
      // join a machine that is already there.
      final FakeShell shell = clientReporting('Running')
        ..answers('tailscale debug prefs', '{"ControlURL":"https://net.example"}');
      expect(await step.check(contextOn(shell, answers: answers)), isA<Satisfied>());
    });

    test('a machine on somebody ELSE\'s network is REFUSED, never moved', () async {
      final FakeShell shell = clientReporting('Running')
        ..answers('tailscale debug prefs', '{"ControlURL":"https://other.example"}');
      final CheckResult answer = await step.check(contextOn(shell, answers: answers));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('DIFFERENT network'));
    });

    test('the join stages the key as a file, joins, and removes the file either way', () async {
      final FakeShell shell = clientReporting('NeedsLogin');
      shell.changes(up, () {
        shell.answers('tailscale status --json', '{"BackendState":"Running"}');
        shell.answers('tailscale debug prefs', '{"ControlURL":"https://net.example"}');
      });
      final FakeFiles files = FakeFiles();
      final StepContext context = contextOn(shell, files: files, answers: answers);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(await step.check(context), isA<Satisfied>());
      expect(files.contents.containsKey('/tmp/staged-key'), isFalse);
      expect(files.written, contains('/tmp/staged-key'));
      expect(files.deleted, contains('/tmp/staged-key'));
    });

    test('the credential never rides the command line', () async {
      final FakeShell shell = clientReporting('NeedsLogin');
      final FakeFiles files = FakeFiles();
      await step.apply(contextOn(shell, files: files, answers: answers)).catchError((Object _) {});
      expect(shell.ran.where((String c) => c.contains('k-join')), isEmpty);
    });

    test('a join the client refuses fails, and the staged key is gone all the same', () async {
      final FakeShell shell = clientReporting('NeedsLogin')
        ..fails(up, stderr: 'invalid key: authkey expired');
      final FakeFiles files = FakeFiles();
      await expectLater(
        step.apply(contextOn(shell, files: files, answers: answers)),
        throwsA(isA<CommandFailed>()),
      );
      expect(files.contents.containsKey('/tmp/staged-key'), isFalse);
    });

    test('an empty credential is refused before anything is staged', () async {
      final FakeShell shell = clientReporting('NeedsLogin');
      final FakeFiles files = FakeFiles();
      await expectLater(
        step.apply(
          contextOn(
            shell,
            files: files,
            answers: const <String, Object>{'login_server': 'https://net.example', 'auth_key': ' '},
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(files.written, isEmpty);
    });
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
