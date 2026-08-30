import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Taking one file OFF the branch a checkout stands on.
///
/// **WHY THE STEP EXISTS.** A branch is the one it was cut from plus what a program writes into
/// it, so every file the source branch carries stands on every branch cut from it — including the few that describe the
/// source branch's own case and contradict the branch they were carried onto. Every other row that shapes a
/// branch WRITES; until this one a program could add to a branch and never subtract.
///
/// What every case here circles is that the removal is decided by the CHECKOUT and not by the row:
/// which branch it stands on, and whether that branch tracks the path at all.
void main() {
  /// The path this row takes off, as the branch tracks it. Deliberately not a path any product of
  /// ours uses: the step is told which file by its row, so a test naming a real one would pass even
  /// if the step reached for that name itself.
  const String path = 'subject/records/only-here.yaml';

  const RemoveBranchFile step = RemoveBranchFile(
    repository: repository,
    refuseOnBranch: base,
    path: path,
  );

  /// A checkout on [head] that does or does not track [path].
  FakeShell on(String head, {required bool tracks}) {
    final FakeShell shell = checkout(head: head);
    const String listing = 'git -C $repository ls-files --error-unmatch -- $path';
    if (tracks) {
      shell.answers(listing, '$path\n');
    } else {
      shell.fails(listing);
    }
    return shell
      ..answers('git -C $repository rm -f -- $path', '')
      ..answers('git -C $repository checkout HEAD -- $path', '');
  }

  test('takes the file off a branch that carries it, and sends exactly that', () async {
    final FakeShell shell = on('apps4.example.com', tracks: true);
    final StepContext context = contextOn(shell: shell);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(shell.ran, contains('git -C $repository rm -f -- $path'));
  });

  test('a branch that does not carry it is the finished state, not work', () async {
    // What a second run of the same program finds, and what a branch cut from one that never
    // carried the file finds. Neither is an error, and neither may send a removal.
    final FakeShell shell = on('apps4.example.com', tracks: false);
    final CheckResult answer = await step.check(contextOn(shell: shell));
    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains(path));
    expect(shell.ran.where((String c) => c.contains('rm -f')), isEmpty);
  });

  test('PLANTED DEFECT: on the branch others are cut from it refuses, and names why', () async {
    // The branch every other is cut FROM. A file taken off it is taken off every branch cut
    // afterwards — so the row refuses there rather than asking anybody.
    final FakeShell shell = on(base, tracks: true);
    final CheckResult answer = await step.check(contextOn(shell: shell));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('every installation is cut from'));
    expect(shell.ran.where((String c) => c.contains('rm -f')), isEmpty);
  });

  test('PLANTED DEFECT: a checkout that will not say which branch it is on is refused', () async {
    final FakeShell shell = on('apps4.example.com', tracks: true)
      ..fails('git -C $repository rev-parse --abbrev-ref HEAD');
    final CheckResult answer = await step.check(contextOn(shell: shell));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('which branch it stands on'));
  });

  test('what it took off, it puts back — index and working tree in one command', () async {
    final FakeShell shell = on('apps4.example.com', tracks: true);
    final StepContext context = contextOn(shell: shell);
    final String? captured = await step.capture(context);
    expect(captured, path);
    await step.undo(context, captured);
    expect(shell.ran, contains('git -C $repository checkout HEAD -- $path'));
  });

  test('a file the branch never carried is not put back by an undo', () async {
    // capture answers null there, and an undo that restored anyway would ADD a file to a branch
    // this row never took one off.
    final FakeShell shell = on('apps4.example.com', tracks: false);
    final StepContext context = contextOn(shell: shell);
    expect(await step.capture(context), isNull);
    await step.undo(context, null);
    expect(shell.ran.where((String c) => c.contains('checkout HEAD')), isEmpty);
  });

  test('the plan says the one command, so a dry run reads as what a run would send', () async {
    final StepPlan plan = await step.plan(contextOn(shell: on('apps4.example.com', tracks: true)));
    expect((plan as ArgvPlan).argv, <String>['git', '-C', repository, 'rm', '-f', '--', path]);
  });
}
