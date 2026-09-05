import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:ansiwise_core/testing.dart';
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

  group('memory is measured against 15,000,000 KiB and not against 16 GiB', () {
    FakeShell withProcessors(int count) => FakeShell()..answers('nproc', '$count\n');

    // The kernel labels the figure `kB` and means kibibytes, which is what the argument says, so
    // the number written here and the number a program row writes are the same unit.
    FakeFiles withMemory(int kibibytes) => FakeFiles(<String, String>{
      '/proc/meminfo': 'MemTotal:       $kibibytes kB\nMemFree:  100 kB\n',
    });

    test('a real 16 GB machine passes, though it reports less than 16 GiB', () async {
      // 15,728,640 KiB is 15 GiB — what a 16 GB machine has left after the kernel's reservations.
      // A floor written as exactly 16 GiB would refuse the very machines the minimum names.
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(15728640)));
      expect(answer, isA<Satisfied>());
    });

    test('a machine below the floor is refused, and the refusal carries both numbers', () async {
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(8000000)));
      expect((answer as Blocked).reason, contains('8000000'));
      expect(answer.reason, contains('15000000'));
    });

    test('too few processors is refused before memory is even read', () async {
      final FakeFiles files = FakeFiles();
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: withProcessors(2), files: files));
      expect((answer as Blocked).reason, contains('2 processors'));
    });

    test('a machine that cannot be measured is refused, not passed', () async {
      final CheckResult answer = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: FakeShell()..fails('nproc'), files: withMemory(16000000)));
      expect(answer, isA<Blocked>());
    });

    test('one KiB below the floor is refused and one KiB above is accepted', () async {
      // The boundary, written in the unit the argument names. Nothing on this path converts, so
      // the figure a program row states is the figure a machine is measured against.
      final CheckResult below = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(14999999)));
      expect((below as Blocked).reason, contains('14999999 KiB'));
      expect(below.reason, contains('15000000 KiB'));

      final CheckResult above = await const RequireMachineSize(
        vcpu: 8,
        memoryKibibytes: 15000000,
      ).check(contextOn(shell: withProcessors(8), files: withMemory(15000001)));
      expect((above as Satisfied).because, contains('15000001 KiB'));
    });
  });

  group('every missing command is named at once', () {
    FakeShell withCommands(Set<String> present) {
      final FakeShell shell = FakeShell();
      for (final String command in <String>['git', 'openssl', 'htpasswd']) {
        if (present.contains(command)) {
          shell.answers(onThePathKey(command), '/usr/bin/$command\n');
        } else {
          shell.fails(onThePathKey(command));
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
      // The pairing comes from the program row, because which package carries a command is a fact
      // of one distribution's archive rather than of the machine this step measures.
      final CheckResult answer = await const RequireCommands(
        <String>['htpasswd'],
        providedBy: <String>['htpasswd=apache2-utils'],
      ).check(contextOn(shell: withCommands(const <String>{})));
      expect(
        (answer as Blocked).reason,
        contains('apache2-utils'),
        reason: 'an operator told to install htpasswd looks for a package that does not exist',
      );
    });

    test('a row that pairs nothing reports every missing command under its own name', () async {
      // The neutral case, and what the declaration falls back to: nothing is invented for a command
      // the row said nothing about, so no operator is sent to a package this step guessed at.
      final CheckResult answer = await const RequireCommands(<String>[
        'htpasswd',
      ]).check(contextOn(shell: withCommands(const <String>{})));
      expect((answer as Blocked).reason, 'not on the path: htpasswd');
    });

    test('half a pairing is no pairing, so the command keeps its own name', () async {
      // An entry with no package behind it would otherwise be kept and reported as "(from )",
      // which sends an operator looking for a package with no name.
      final CheckResult answer = await const RequireCommands(
        <String>['htpasswd'],
        providedBy: <String>['htpasswd=', '=apache2-utils', 'htpasswd'],
      ).check(contextOn(shell: withCommands(const <String>{})));
      expect((answer as Blocked).reason, 'not on the path: htpasswd');
    });
  });

  group('free disk', () {
    // `-k` makes every block 1024 bytes, so what df writes and what the argument names are one
    // unit and the step converts nothing between them.
    FakeShell dfReporting(int availableKibibytes) => FakeShell()
      ..answers(
        'df -Pk /',
        'Filesystem     1024-blocks     Used Available Capacity Mounted on\n'
            '/dev/sda1        104857600 20971520 $availableKibibytes      21% /\n',
      );

    test('enough room is satisfied', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        freeKibibytes: 60000000,
      ).check(contextOn(shell: dfReporting(80000000)));
      expect(answer, isA<Satisfied>());
    });

    test('too little is refused with both numbers', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        freeKibibytes: 60000000,
      ).check(contextOn(shell: dfReporting(20000000)));
      expect((answer as Blocked).reason, contains('20000000 KiB'));
      expect(answer.reason, contains('60000000 KiB'));
    });

    test('one KiB below the floor is refused and one KiB above is accepted', () async {
      // The boundary, written in the unit the argument names. The division by a million that used
      // to stand here made 40,960,000 KiB and 40,000,000 KiB the same answer.
      final CheckResult below = await const RequireFreeDisk(
        path: '/',
        freeKibibytes: 40000000,
      ).check(contextOn(shell: dfReporting(39999999)));
      expect((below as Blocked).reason, contains('39999999 KiB'));
      expect(below.reason, contains('40000000 KiB'));

      final CheckResult above = await const RequireFreeDisk(
        path: '/',
        freeKibibytes: 40000000,
      ).check(contextOn(shell: dfReporting(40000001)));
      expect((above as Satisfied).because, contains('40000001 KiB'));
    });

    test('output it cannot read is refused, not treated as enough', () async {
      final CheckResult answer = await const RequireFreeDisk(
        path: '/',
        freeKibibytes: 60000000,
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
