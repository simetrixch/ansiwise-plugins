import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// The whole of `deploy-host`, run against a machine that exists only in memory.
///
/// This is the test that would have caught most of what went wrong in the shell: it runs the real
/// program file, through the real registry, in every mode, and looks at what came out.
void main() {
  Program declared() =>
      loadProgram(File('programs/deploy-host.yaml').readAsStringSync(), where: 'deploy-host.yaml');

  ResolvedProgram deployHost() => const ProgramResolver(executionRegistry).resolve(declared());

  /// The key this machine is to be reached by, as an operator would hand one over.
  const String operatorKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExampleKeyForTheTemplateOnly operator@example.com';

  /// What an operator supplies, put through the program's OWN declaration.
  ///
  /// Validated rather than handed straight to the runner, so this fixture cannot drift from what
  /// `deploy-host.yaml` asks for: an answer the program stopped declaring, or a required one nobody
  /// gave, fails here instead of leaving a step reading an empty bag.
  Arguments answered() => declared().answers.validate(<String, Object?>{
    'operator_user': 'operator',
    'operator_public_key': operatorKey,
  }, program: 'deploy-host');

  /// A machine that satisfies every gate and has nothing installed.
  ({FakeShell shell, FakeFiles files}) bareMachine() {
    final FakeShell shell = FakeShell()
      ..answers('nproc', '8\n')
      ..answers(
        'df -Pk /',
        'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
            '/dev/sda1 104857600 20971520 80000000 21% /\n',
      )
      ..answers('apt-get --dry-run autoremove', 'Remv oldpackage [1.0]\n')
      ..answers('getent passwd operator', 'operator:x:1000:1000::/home/operator:/bin/bash\n')
      ..answers('sshd -T', 'port 22\npubkeyauthentication yes\npasswordauthentication yes\n')
      ..answers('stat -c %a /home/operator', '755\n')
      ..answers('stat -c %a /home/operator/.ssh', '700\n')
      ..answers('stat -c %a /home/operator/.ssh/authorized_keys', '600\n');
    for (final String package in <String>['git', 'openssl', 'curl', 'jq', 'apache2-utils']) {
      shell.fails('dpkg-query -W -f=\${Status} $package');
    }
    // Two lists, and they mean different things. `toolsAssumed` is what a fresh Ubuntu already
    // carries and this program only USES, asked for at the head before anything is written. The
    // five after it are what this program INSTALLS, asked for again afterwards as the proof that the
    // install really landed — an install can succeed and leave nothing behind.
    for (final String command in <String>[
      ...toolsAssumed,
      'git',
      'openssl',
      'curl',
      'jq',
      'htpasswd',
    ]) {
      shell.answers('command -v $command', '/usr/bin/$command\n');
    }

    final FakeFiles files = FakeFiles(<String, String>{
      '/etc/os-release': 'ID=ubuntu\nVERSION_ID="26.04"\n',
      '/proc/meminfo': 'MemTotal:       16087564 kB\n',
      '/var/cache/apt/archives/one.deb': '',
      '/var/cache/apt/archives/two.deb': '',
    });
    return (shell: shell, files: files);
  }

  RunRecord header(Mode mode, FakeClock clock) => RunRecord(
    id: const RunId('20260807T120000Z-1'),
    program: const ProgramName('deploy-host'),
    mode: mode,
    argv: const <String>['ansiwise', 'deploy-host'],
    start: clock.now(),
    stage: const Stage('dev'),
    role: const Role('master'),
    fqdn: const Fqdn('m1.example.com'),
    commit: 'abc1234',
    fingerprint: 'f',
  );

  Future<({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder})> run(
    Mode mode,
  ) async {
    final ({FakeShell shell, FakeFiles files}) machine = bareMachine();
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final RunRecord record = await Runner(
      machine: Machine(
        shell: machine.shell,
        files: machine.files,
        http: FakeHttp(),
        clock: clock,
        entropy: FakeEntropy(),
      ),
      recorder: recorder,
      redactor: Redactor.none,
    ).run(program: deployHost(), mode: mode, header: header(mode, clock), answers: answered());
    return (record: record, shell: machine.shell, files: machine.files, recorder: recorder);
  }

  test('the program resolves against the registry', () {
    expect(deployHost().steps, hasLength(10));
  });

  test('every value this machine states about itself is an answer, not an argument', () {
    // The defect this replaces: the account and the key stood in the program file, so the program
    // shipped a key NOBODY HOLDS — install_authorized_key would install it, the gate after it would
    // confirm it was installed, and the operator who ran it would still be locked out.
    //
    // What is left below is the platform's own floor and the platform's own package list: the same
    // on every machine, decided by this product rather than by whoever is installing it.
    expect(<String>[
      for (final ArgumentSpec spec in declared().answers.specs) spec.name,
    ], containsAll(<String>[InstallAuthorizedKey.userAnswer, InstallAuthorizedKey.keyAnswer]));

    for (final ResolvedStep step in deployHost().steps) {
      expect(
        step.entry.arguments.names,
        everyElement(
          isIn(<String>[
            'release',
            'vcpu',
            'memory_kilobytes',
            'path',
            'gigabytes',
            'packages',
            'commands',
          ]),
        ),
        reason:
            '${step.entry.step} is given something in the program file that names one machine, '
            'and a program file ships to every installation',
      );
    }
  });

  test('the gate proves the key that was installed, not a second one', () {
    // A second pair of names here would let the gate pass on a key nobody installed. It reads what
    // install_authorized_key wrote, so it reads it under the same two names.
    expect(RequireKeyLoginPossible.answers, same(InstallAuthorizedKey.answers));
  });

  group('--mode dry', () {
    test('changes nothing on the machine', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a dry run may only run commands a step declared as observing',
      );
    });

    test('every step comes back green', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);
      expect(it.record.exitCode, 0);
      for (final StepRecord step in it.record.steps) {
        expect(step.verdict, isA<Succeeded>(), reason: '${step.step} was not green');
      }
    });

    test('it says what it would install, and what it would delete', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      final List<String> planned = <String>[
        for (final StepRecord step in it.record.steps)
          if (step.plan case final StepPlan plan) plan.summary,
      ];
      expect(planned, contains(contains('apt-get install --yes git openssl')));
      expect(it.recorder.notes, contains('2 downloaded archives would be deleted'));
      expect(it.recorder.notes, contains('1 package would be removed'));
    });

    test('a step that would have nothing to do plans nothing', () async {
      // The commands are already on the path, so the gate that checks them is satisfied and never
      // plans. That is what idempotence looks like inside a dry run.
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);
      final StepRecord commands = it.record.steps.firstWhere(
        (StepRecord s) => s.step == const StepName('require_commands'),
      );
      expect(commands.plan, isA<NothingPlan>());
    });
  });

  group('--mode run', () {
    test('it installs what is missing and reaches the end', () async {
      // dpkg answers "not installed" throughout, so the install step's postcondition never holds and
      // the run stops there. That is the correct behaviour and it is what is being asserted: a step
      // whose work did not take effect fails, whatever apt returned.
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(it.shell.ran, contains('apt-get update'));
      expect(it.shell.ran, contains('apt-get install --yes git openssl curl jq apache2-utils'));
      expect(it.record.exitCode, 1, reason: 'the postcondition never held');
    });

    test('a machine below the memory floor is refused before anything is installed', () async {
      final ({FakeShell shell, FakeFiles files}) machine = bareMachine();
      machine.files.contents['/proc/meminfo'] = 'MemTotal:       4000000 kB\n';
      final FakeClock clock = FakeClock();

      final RunRecord record =
          await Runner(
            machine: Machine(
              shell: machine.shell,
              files: machine.files,
              http: FakeHttp(),
              clock: clock,
              entropy: FakeEntropy(),
            ),
            recorder: MemoryRecorder(clock),
            redactor: Redactor.none,
          ).run(
            program: deployHost(),
            mode: Mode.run,
            header: header(Mode.run, clock),
            answers: answered(),
          );

      expect(record.exitCode, 1);
      expect(record.steps.last.verdict, isA<Died>());
      expect((record.steps.last.verdict as Died).reason, contains('4000000'));
      expect(
        machine.shell.ran,
        isNot(contains('apt-get update')),
        reason: 'nothing may be installed onto a machine that was refused',
      );
    });
  });

  group('--mode test', () {
    test('it measures the machine and stops there', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.test);

      expect(it.record.exitCode, 0);
      expect(it.shell.ran, contains('nproc'));
      expect(it.shell.ran, isNot(contains('apt-get update')), reason: 'a test run does no work');
    });
  });

  group('a gate that verifies an earlier step', () {
    test('does not fail a test run, because nothing has run for it to verify', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.test);

      final StepRecord gate = it.record.steps.firstWhere(
        (StepRecord s) => s.step == const StepName('require_key_login_possible'),
      );
      expect(gate.verdict, isA<Succeeded>());
      expect(
        it.recorder.notes.join('\n'),
        contains('not checked before the steps it verifies have run'),
      );
    });

    test('says in a dry run what it would check, rather than what is not there yet', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      final StepRecord gate = it.record.steps.firstWhere(
        (StepRecord s) => s.step == const StepName('require_key_login_possible'),
      );
      switch (gate.plan) {
        case final NothingPlan plan:
          expect(plan.because, contains('would check this once the steps before it have run'));
        default:
          fail('a verifying gate must say what it would check');
      }
    });

    test('a gate that measures the machine as found still fails a test run', () async {
      // The distinction this rests on: too little memory is as true before a run as during one, and
      // a test run that hid it would be hiding the answer the operator came for.
      final ({FakeShell shell, FakeFiles files}) machine = bareMachine();
      machine.files.contents['/proc/meminfo'] = 'MemTotal:       4000000 kB\n';
      final FakeClock clock = FakeClock();

      final RunRecord record =
          await Runner(
            machine: Machine(
              shell: machine.shell,
              files: machine.files,
              http: FakeHttp(),
              clock: clock,
              entropy: FakeEntropy(),
            ),
            recorder: MemoryRecorder(clock),
            redactor: Redactor.none,
          ).run(
            program: deployHost(),
            mode: Mode.test,
            header: header(Mode.test, clock),
            answers: answered(),
          );

      expect(record.exitCode, 1);
      expect((record.steps.last.verdict as Died).reason, contains('4000000'));
    });
  });

  test('the key is installed before anything proves it, and before the password could go', () {
    final List<StepName> order = <StepName>[
      for (final ResolvedStep s in deployHost().steps) s.entry.step,
    ];
    expect(
      order.indexOf(const StepName('install_authorized_key')),
      lessThan(order.indexOf(const StepName('require_key_login_possible'))),
      reason: 'a proof that runs before the thing it proves is not a proof',
    );
  });

  group('a tool this program only uses, taken off the machine', () {
    // The case the head gate exists for: an image somebody trimmed. Without it the run gets as far
    // as the package install, writes to the machine, and then fails at a step whose message is about
    // whatever that step was doing rather than about a command that is not there.

    Future<RunRecord> runWithout(String absent) async {
      final ({FakeShell shell, FakeFiles files}) machine = bareMachine();
      machine.shell.fails('command -v $absent');
      final FakeClock clock = FakeClock();
      return Runner(
        machine: Machine(
          shell: machine.shell,
          files: machine.files,
          http: FakeHttp(),
          clock: clock,
          entropy: FakeEntropy(),
        ),
        recorder: MemoryRecorder(clock),
        redactor: Redactor.none,
      ).run(
        program: deployHost(),
        mode: Mode.run,
        header: header(Mode.run, clock),
        answers: answered(),
      );
    }

    test('the run stops, and it stops at the gate', () async {
      final RunRecord record = await runWithout('dpkg-query');
      expect(record.exitCode, isNot(0));
      expect(
        record.steps.first.step,
        const StepName('require_commands'),
        reason: 'the gate is what ran; anything else means the run had already started working',
      );
    });

    test('nothing was installed before it stopped', () async {
      final RunRecord record = await runWithout('dpkg-query');
      expect(
        record.steps.map((StepRecord s) => s.step),
        isNot(contains(const StepName('install_packages'))),
        reason:
            'this is the whole point of the gate: a machine that was never going to work is refused '
            'before anything is written to it',
      );
    });

    test('the refusal names the command, not the step that tripped over it', () async {
      final RunRecord record = await runWithout('dpkg-query');
      final Verdict verdict = record.steps.first.verdict;
      expect(
        verdict,
        isA<Died>(),
        reason: 'the gate ends the run; its policy in the program is die',
      );
      expect(
        (verdict as Died).reason,
        contains('dpkg-query'),
        reason:
            'an operator reads the refusal and installs something; a message about a package query '
            'that failed sends them looking at the package manager instead',
      );
    });
  });
}

/// What a fresh Ubuntu carries and this program only uses.
///
/// Kept beside the fixture rather than repeated in it, because it is also the list the head gate of
/// programs/deploy-host.yaml asks for — and a fixture that answered for a different set would be a
/// machine no operator has.
const List<String> toolsAssumed = <String>[
  'apt-get',
  'dpkg-query',
  'nproc',
  'df',
  'getent',
  'sshd',
  'stat',
  'chown',
];
