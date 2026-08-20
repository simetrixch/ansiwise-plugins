import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// The step that reads a recorded value off the branch a checkout stands on and publishes it.
///
/// What is asserted is the whole contract: the COMMITTED byte is read and never the working copy,
/// the `<branch>` slot is filled with the branch git names, both line shapes yield the value, and
/// every way of there being no value is a refusal that publishes nothing — because the row taking
/// the measurement cannot tell an empty publication from a real one afterwards.
void main() {
  /// The file the branch records its value in, named for the branch as such files are.
  const String path = 'records/<branch>.yaml';

  /// The key whose value the step publishes.
  const String key = 'pin';

  const MeasureValueInBranchFile step = MeasureValueInBranchFile(
    repository: repository,
    path: path,
    key: key,
  );

  /// A context whose measurements land in [published], so a test can read what a later row would.
  (StepContext, Measurements) measuring({required FakeShell shell}) {
    final Measurements published = Measurements();
    return (
      StepContext(
        shell: shell,
        files: FakeFiles(),
        http: FakeHttp(),
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const SilentLog(),
        step: const StepName('under_test'),
        arguments: Arguments.none,
        answers: Arguments.none,
        measurements: published.forStep(
          const StepName('under_test'),
          MeasureValueInBranchFile.publishes,
        ),
        facts: Facts.none,
      ),
      published,
    );
  }

  /// A checkout standing on [branch] whose committed file at [named] holds [content].
  FakeShell recording({String branch = 'm1.example.com', required String content}) => FakeShell()
    ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n')
    ..answers('git -C $repository show HEAD:records/$branch.yaml', content);

  group('the recorded value is published', () {
    test('off a "key: value" line, under the file the <branch> slot names', () async {
      final (StepContext context, Measurements published) = measuring(
        shell: recording(content: 'name: m1.example.com\npin: v1.2.3\n'),
      );

      final CheckResult answer = await step.check(context);
      expect(answer, isA<Satisfied>());
      expect(published.valueOf(const MeasurementName('value')), 'v1.2.3');
    });

    test('off a "KEY=value" line, because both notations record one value per line', () async {
      const MeasureValueInBranchFile upper = MeasureValueInBranchFile(
        repository: repository,
        path: path,
        key: 'PIN',
      );
      final (StepContext context, Measurements published) = measuring(
        shell: recording(content: 'PIN=v1.2.3\n'),
      );

      expect(await upper.check(context), isA<Satisfied>());
      expect(published.valueOf(const MeasurementName('value')), 'v1.2.3');
    });

    test('with the notation\'s own quotes taken off, because they are not the value\'s', () async {
      final (StepContext context, Measurements published) = measuring(
        shell: recording(content: "pin: 'v1.2.3'\n"),
      );

      await step.check(context);
      expect(published.valueOf(const MeasurementName('value')), 'v1.2.3');
    });

    test(
      'off the named key alone — a longer key merely beginning with it is another key',
      () async {
        final (StepContext context, Measurements published) = measuring(
          shell: recording(content: 'pin-note: wrong\npin: right\n'),
        );

        await step.check(context);
        expect(published.valueOf(const MeasurementName('value')), 'right');
      },
    );

    test('it only measures, and changes nothing', () async {
      final FakeShell shell = recording(content: 'pin: v1.2.3\n');
      final (StepContext context, _) = measuring(shell: shell);

      await step.check(context);
      expect(shell.commands.where((Command c) => !c.observes), isEmpty);
    });
  });

  group('every way of there being no value refuses and publishes nothing', () {
    test('a checkout standing on no branch', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'HEAD\n');
      final (StepContext context, Measurements published) = measuring(shell: shell);

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains('no branch checked out'));
      expect(published.valueOf(const MeasurementName('value')), isNull);
    });

    test('a branch that carries no such file, named with the file and the branch', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'm1.example.com\n')
        ..fails(
          'git -C $repository show HEAD:records/m1.example.com.yaml',
          stderr: 'fatal: path does not exist',
        );
      final (StepContext context, Measurements published) = measuring(shell: shell);

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains('records/m1.example.com.yaml'));
      expect(answer.reason, contains('m1.example.com'));
      expect(published.valueOf(const MeasurementName('value')), isNull);
    });

    test('a file that records no line for the key', () async {
      final (StepContext context, Measurements published) = measuring(
        shell: recording(content: 'name: m1.example.com\n'),
      );

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains('"$key"'));
      expect(published.valueOf(const MeasurementName('value')), isNull);
    });

    test('a key whose line holds nothing after the separator', () async {
      final (StepContext context, Measurements published) = measuring(
        shell: recording(content: 'pin:\n'),
      );

      expect(await step.check(context), isA<Blocked>());
      expect(published.valueOf(const MeasurementName('value')), isNull);
    });

    test('a path still carrying a slot this step does not fill, named as that', () async {
      const MeasureValueInBranchFile missized = MeasureValueInBranchFile(
        repository: repository,
        path: 'records/<branch>-<stage>.yaml',
        key: key,
      );
      final (StepContext context, _) = measuring(shell: recording(content: 'pin: v1.2.3\n'));

      final CheckResult answer = await missized.check(context);
      expect((answer as Blocked).reason, contains('<stage>'));
    });
  });

  group('the file may be named for something other than the branch', () {
    /// The name of the answer that names the file, which is NOT the branch the checkout stands on.
    const String fqdn = 's1.example.com';

    const MeasureValueInBranchFile named = MeasureValueInBranchFile(
      repository: repository,
      path: 'clusters/active/<fqdn>.yaml',
      key: key,
      runAnswer: 'fqdn',
    );

    /// A context standing on [branch] whose run answers [fqdn] under "fqdn".
    (StepContext, Measurements) answering({
      required FakeShell shell,
      Arguments answers = const Arguments(<String, Object>{'fqdn': fqdn}),
    }) {
      final Measurements published = Measurements();
      return (
        StepContext(
          shell: shell,
          files: FakeFiles(),
          http: FakeHttp(),
          clock: FakeClock(),
          entropy: FakeEntropy(),
          log: const SilentLog(),
          step: const StepName('under_test'),
          arguments: Arguments.none,
          answers: answers,
          measurements: published.forStep(
            const StepName('under_test'),
            MeasureValueInBranchFile.publishes,
          ),
          facts: Facts.none,
        ),
        published,
      );
    }

    test('the slot the row names is filled from that answer, off another branch', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'master\n')
        ..answers('git -C $repository show HEAD:clusters/active/$fqdn.yaml', 'pin: v1.2.3\n');
      final (StepContext context, Measurements published) = answering(shell: shell);

      expect(await named.check(context), isA<Satisfied>());
      expect(published.valueOf(const MeasurementName('value')), 'v1.2.3');
    });

    test('the branch slot stays the branch, so a row may carry both', () async {
      const MeasureValueInBranchFile both = MeasureValueInBranchFile(
        repository: repository,
        path: 'records/<branch>/<fqdn>.yaml',
        key: key,
        runAnswer: 'fqdn',
      );
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'master\n')
        ..answers('git -C $repository show HEAD:records/master/$fqdn.yaml', 'pin: v1.2.3\n');
      final (StepContext context, Measurements published) = answering(shell: shell);

      expect(await both.check(context), isA<Satisfied>());
      expect(published.valueOf(const MeasurementName('value')), 'v1.2.3');
    });

    test('a run holding no such answer leaves the slot over, and that is refused', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'master\n');
      final (StepContext context, Measurements published) = answering(
        shell: shell,
        answers: Arguments.none,
      );

      final CheckResult answer = await named.check(context);
      expect((answer as Blocked).reason, contains('<fqdn>'));
      expect(published.valueOf(const MeasurementName('value')), isNull);
    });
  });

  group('counter-probe: a program row using the slot', () {
    /// The row this argument was found missing by: a checkout standing on ONE installation's
    /// branch, reading the map another installation is recorded under. Written as a program file
    /// rather than as a constructed step, because what was missing was the ARGUMENT, and the
    /// resolver is the only thing that reads one.
    const String program =
        '''
name: read-recorded-release
roles: [master]
answers:
  - name: fqdn
    kind: text
    describes: the domain name of the installation whose map records the release
steps:
  - step: measure_value_in_branch_file
    repository: $repository
    path: clusters/active/<fqdn>.yaml
    key: release
    run_answer: fqdn
    on_failure: exit
''';

    test('resolves against the registry, and before the argument existed it did not', () {
      expect(
        () => const ProgramResolver(
          gitRegistry,
        ).resolve(loadProgram(program, where: 'read-recorded-release.yaml')),
        returnsNormally,
      );
    });

    test('and the answer it names has to be one the program declares', () {
      const String undeclared =
          '''
name: read-recorded-release
roles: [master]
steps:
  - step: measure_value_in_branch_file
    repository: $repository
    path: clusters/active/<fqdn>.yaml
    key: release
    run_answer: fqdn
    on_failure: exit
''';

      expect(
        () => const ProgramResolver(
          gitRegistry,
        ).resolve(loadProgram(undeclared, where: 'read-recorded-release.yaml')),
        throwsA(
          isA<ProgramInvalid>().having(
            (ProgramInvalid e) => e.message,
            'message',
            contains('names the answer "fqdn"'),
          ),
        ),
      );
    });
  });
}
