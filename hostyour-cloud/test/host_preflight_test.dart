import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// The gates that refuse a machine before anything is written to it.
///
/// Every one of them exists because a real machine failed halfway through otherwise, and every one
/// of them measures rather than assumes. They change nothing, so a test needs no machine — only a
/// fake that answers the way one would.
void main() {
  StepContext contextOn({FakeShell? shell, FakeFiles? files}) {
    final FakeShell theShell = shell ?? FakeShell();
    final FakeFiles theFiles = files ?? FakeFiles();
    return StepContext(
      shell: theShell,
      files: theFiles,
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const _SilentLog(),
      step: const StepName('under_test'),
      arguments: Arguments.none,
      facts: Facts.none,
    );
  }

  group('the operating system release is a pin, not a preference', () {
    test('the pinned release is satisfied', () async {
      final CheckResult answer = await const RequirePinnedUbuntu('26.04').check(
        contextOn(
          files: FakeFiles(<String, String>{
            '/etc/os-release': 'ID=ubuntu\nVERSION_ID="26.04"\nPRETTY_NAME="Ubuntu 26.04 LTS"\n',
          }),
        ),
      );
      expect(answer, isA<Satisfied>());
    });

    test('another release is refused, and the refusal names both', () async {
      final CheckResult answer = await const RequirePinnedUbuntu('26.04').check(
        contextOn(
          files: FakeFiles(<String, String>{'/etc/os-release': 'ID=ubuntu\nVERSION_ID=24.04\n'}),
        ),
      );
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('24.04'));
      expect(answer.reason, contains('26.04'));
    });

    test('another distribution is refused by name', () async {
      final CheckResult answer = await const RequirePinnedUbuntu('26.04').check(
        contextOn(
          files: FakeFiles(<String, String>{'/etc/os-release': 'ID=debian\nVERSION_ID="12"\n'}),
        ),
      );
      expect((answer as Blocked).reason, contains('debian'));
    });

    test('a value is read whether or not it is quoted', () async {
      const RequirePinnedUbuntu step = RequirePinnedUbuntu('26.04');
      for (final String line in <String>['VERSION_ID=26.04', 'VERSION_ID="26.04"']) {
        final CheckResult answer = await step.check(
          contextOn(files: FakeFiles(<String, String>{'/etc/os-release': 'ID=ubuntu\n$line\n'})),
        );
        expect(answer, isA<Satisfied>(), reason: line);
      }
    });

    test('a machine with no os-release is refused rather than assumed', () async {
      final CheckResult answer = await const RequirePinnedUbuntu('26.04').check(contextOn());
      expect(answer, isA<Blocked>());
    });
  });

  group('memory is measured against 15,000,000 kB and not against 16 GiB', () {
    FakeShell withProcessors(int count) => FakeShell()..answers('nproc', '$count\n');

    FakeFiles withMemory(int kilobytes) => FakeFiles(<String, String>{
      '/proc/meminfo': 'MemTotal:       $kilobytes kB\nMemFree:  100 kB\n',
    });

    test('a real 16 GB machine passes, though it reports less than 16 GiB', () async {
      // 15,728,640 kB is 15 GiB — what a 16 GB machine has left after the kernel's reservations.
      // A floor written as exactly 16 GiB would refuse the very machines the minimum names.
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKilobytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(15728640)));
      expect(answer, isA<Satisfied>());
    });

    test('a machine below the floor is refused, and the refusal carries both numbers', () async {
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKilobytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(8000000)));
      expect((answer as Blocked).reason, contains('8000000'));
      expect(answer.reason, contains('15000000'));
    });

    test('too few processors is refused before memory is even read', () async {
      final FakeFiles files = FakeFiles();
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKilobytes: 15000000,
      ).check(contextOn(shell: withProcessors(2), files: files));
      expect((answer as Blocked).reason, contains('2 processors'));
    });

    test('a machine that cannot be measured is refused, not passed', () async {
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKilobytes: 15000000,
      ).check(contextOn(shell: FakeShell()..fails('nproc'), files: withMemory(16000000)));
      expect(answer, isA<Blocked>());
    });
  });

  group('every missing command is named at once', () {
    FakeShell withCommands(Set<String> present) {
      final FakeShell shell = FakeShell();
      for (final String command in <String>['git', 'openssl', 'htpasswd']) {
        if (present.contains(command)) {
          shell.answers('command -v $command', '/usr/bin/$command\n');
        } else {
          shell.fails('command -v $command');
        }
      }
      return shell;
    }

    test('all present is satisfied', () async {
      final CheckResult answer = await const RequireCommands(<String>[
        'git',
        'openssl',
      ]).check(contextOn(shell: withCommands(<String>{'git', 'openssl'})));
      expect(answer, isA<Satisfied>());
    });

    test('two missing are both named, not just the first', () async {
      final CheckResult answer = await const RequireCommands(<String>[
        'git',
        'openssl',
        'htpasswd',
      ]).check(contextOn(shell: withCommands(<String>{'git'})));
      expect((answer as Blocked).reason, contains('openssl'));
      expect(answer.reason, contains('htpasswd'));
      expect(answer.reason, isNot(contains('git')));
    });

    test('a command whose package has another name says which package', () async {
      final CheckResult answer = await const RequireCommands(<String>[
        'htpasswd',
      ]).check(contextOn(shell: withCommands(const <String>{})));
      expect(
        (answer as Blocked).reason,
        contains('apache2-utils'),
        reason: 'an operator told to install htpasswd looks for a package that does not exist',
      );
    });
  });

  group('free disk', () {
    FakeShell dfReporting(int availableKilobytes) => FakeShell()
      ..answers(
        'df -Pk /',
        'Filesystem     1024-blocks     Used Available Capacity Mounted on\n'
            '/dev/sda1        104857600 20971520 $availableKilobytes      21% /\n',
      );

    test('enough room is satisfied', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        gigabytes: 60,
      ).check(contextOn(shell: dfReporting(80000000)));
      expect(answer, isA<Satisfied>());
    });

    test('too little is refused with both numbers', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        gigabytes: 60,
      ).check(contextOn(shell: dfReporting(20000000)));
      expect((answer as Blocked).reason, contains('20 GB'));
      expect(answer.reason, contains('60 GB'));
    });

    test('output it cannot read is refused, not treated as enough', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        gigabytes: 60,
      ).check(contextOn(shell: FakeShell()..answers('df -Pk /', 'nothing useful\n')));
      expect(answer, isA<Blocked>());
    });
  });

  group('a gate never asks to be applied', () {
    test('its plan says it only measures', () async {
      final StepPlan plan = await const RequirePinnedUbuntu('26.04').plan(contextOn());
      expect(plan, isA<NothingPlan>());
    });
  });
}

final class _SilentLog implements StepLog {
  const _SilentLog();

  @override
  void info(String message) {}

  @override
  void warn(String message) {}
}
