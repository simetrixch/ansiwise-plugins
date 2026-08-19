import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// The step that carries one committed file of a branch to a destination another row decides about.
///
/// The property everything here circles is inheritance without re-deciding: the COMMITTED byte
/// travels, the working copy never does, and a destination already holding the byte is the finished
/// state rather than work to redo.
void main() {
  /// The branch the source checkout stands on.
  const String sourceBranch = 'm1.example.com';

  /// The stage this run holds, filling the `<stage>` slot in both paths.
  const String stage = 'dev';

  /// What the branch commits at the source path.
  const String recorded = 'name: m1.example.com\npin: v1.2.3\n';

  const CopyBranchFile step = CopyBranchFile(
    repository: repository,
    path: 'records/<branch>-<stage>.yaml',
    destination: '/srv/elsewhere/records/<stage>.yaml',
    fileMode: 420,
    runAnswer: 'stage',
  );

  /// Where the copy lands once every slot is filled.
  const String destination = '/srv/elsewhere/records/$stage.yaml';

  FakeShell source({String branch = sourceBranch, String content = recorded}) => FakeShell()
    ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n')
    ..answers('git -C $repository show HEAD:records/$branch-$stage.yaml', content);

  StepContext contextWith({required FakeShell shell, required FakeFiles files}) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': stage}),
    facts: Facts.none,
  );

  group('the committed byte travels to the destination', () {
    test('written with the row\'s mode, under both slots filled', () async {
      final FakeFiles files = FakeFiles();
      final StepContext context = contextWith(shell: source(), files: files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(files.contents[destination], recorded);
      expect(files.modes[destination], 420);
    });

    test('a second run finds the destination already holding it and does nothing', () async {
      final FakeFiles files = FakeFiles(<String, String>{destination: recorded});
      final StepContext context = contextWith(shell: source(), files: files);

      final CheckResult answer = await step.check(context);
      expect(answer, isA<Satisfied>());
      expect(files.written, isEmpty);
    });

    test('a destination holding something else is work to do, and the plan says what', () async {
      final FakeFiles files = FakeFiles(<String, String>{destination: 'pin: v0.9.0\n'});
      final StepContext context = contextWith(shell: source(), files: files);

      expect(await step.check(context), isA<Ready>());
      final StepPlan plan = await step.plan(context);
      expect((plan as DiffPlan).before, 'pin: v0.9.0\n');
      expect(plan.after, recorded);
      expect(plan.path, destination);
    });
  });

  group('what cannot be read is refused, each cause by its own name', () {
    test('a source checkout standing on no branch', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', 'HEAD\n');
      final StepContext context = contextWith(shell: shell, files: FakeFiles());

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains('no branch checked out'));
    });

    test('a branch that carries no file at the source path', () async {
      final FakeShell shell = FakeShell()
        ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$sourceBranch\n')
        ..fails('git -C $repository show HEAD:records/$sourceBranch-$stage.yaml');
      final StepContext context = contextWith(shell: shell, files: FakeFiles());

      final CheckResult answer = await step.check(context);
      expect((answer as Blocked).reason, contains('records/$sourceBranch-$stage.yaml'));
    });

    test('a path still carrying a slot nothing filled', () async {
      const CopyBranchFile missized = CopyBranchFile(
        repository: repository,
        path: 'records/<branch>-<version>.yaml',
        destination: destination,
        fileMode: 420,
        runAnswer: 'stage',
      );
      final StepContext context = contextWith(shell: source(), files: FakeFiles());

      final CheckResult answer = await missized.check(context);
      expect((answer as Blocked).reason, contains('slot'));
    });
  });

  group('the undo puts the destination back the way it stood', () {
    test('what was there is restored', () async {
      final FakeFiles files = FakeFiles(<String, String>{destination: 'pin: v0.9.0\n'});
      final StepContext context = contextWith(shell: source(), files: files);

      final String? captured = await step.capture(context);
      await step.apply(context);
      expect(files.contents[destination], recorded);

      await step.undo(context, captured);
      expect(files.contents[destination], 'pin: v0.9.0\n');
    });

    test('a destination that was not there is gone again', () async {
      final FakeFiles files = FakeFiles();
      final StepContext context = contextWith(shell: source(), files: files);

      final String? captured = await step.capture(context);
      await step.apply(context);
      await step.undo(context, captured);

      expect(files.contents.containsKey(destination), isFalse);
      expect(files.deleted, contains(destination));
    });
  });
}
