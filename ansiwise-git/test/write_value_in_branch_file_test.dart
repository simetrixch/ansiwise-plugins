import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// Recording one value in one tracked file, and the ways a file quietly ends up with two answers to
/// one question.
void main() {
  const String map = 'clusters/active/$branch.yaml';
  const String tag = '1.2.3-alpha-20260824120000';

  const WriteValueInBranchFile step = WriteValueInBranchFile(
    repository: repository,
    path: 'clusters/active/<branch>.yaml',
    key: 'release',
    valueAnswer: 'release_tag',
    fileMode: 420,
  );

  FakeShell onBranch() =>
      FakeShell()..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n');

  FakeFiles carrying(String contents) => FakeFiles(<String, String>{'$repository/$map': contents});

  StepContext held(FakeFiles files, {String? value = tag}) => contextOn(
    shell: onBranch(),
    files: files,
    name: branch,
    also: <String, Object>{'release_tag': ?value},
  );

  const String before = 'fqdn: $branch\nstage: dev\nrole: master\nrelease:\n';

  test('a file recording no value gains one, and the second run has nothing to do', () async {
    final FakeFiles files = carrying(before);

    expect(await step.check(held(files)), isA<Ready>());
    await step.apply(held(files));

    expect(files.contents['$repository/$map'], contains('release: $tag'));
    expect(await step.check(held(files)), isA<Satisfied>());
  });

  test('a file already recording another value is edited WHERE THE LINE STANDS', () async {
    // Appending instead would leave two lines for one key, and what reads them takes one — so the
    // next run would decide the question again, and nothing would report which answer won.
    final FakeFiles files = carrying(
      'fqdn: $branch\nrelease: 1.0.0-alpha-20260101000000\nstage: dev\n',
    );

    await step.apply(held(files));

    final String after = files.contents['$repository/$map']!;
    expect(after.split('\n').where((String l) => l.startsWith('release:')).length, 1);
    expect(after, contains('release: $tag'));
    expect(
      after.indexOf('release:'),
      lessThan(after.indexOf('stage:')),
      reason: 'the order a person put the file in survives the edit',
    );
  });

  test('THE INNOCENT NEIGHBOUR: everything else in the file is left exactly alone', () async {
    final FakeFiles files = carrying(before);

    await step.apply(held(files));

    final String after = files.contents['$repository/$map']!;
    for (final String kept in <String>['fqdn: $branch', 'stage: dev', 'role: master']) {
      expect(after, contains(kept));
    }
  });

  test('a run holding no such answer is refused by that answer\'s name', () async {
    // Writing an empty one would record an absence as a value, and what reads it cannot tell the
    // two apart.
    final CheckResult answer = await step.check(held(carrying(before), value: null));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('release_tag'));
  });

  test('a path still carrying a slot nothing fills is refused as written', () async {
    const WriteValueInBranchFile unfilled = WriteValueInBranchFile(
      repository: repository,
      path: 'clusters/active/<stage>.yaml',
      key: 'release',
      valueAnswer: 'release_tag',
      fileMode: 420,
    );

    final CheckResult answer = await unfilled.check(held(carrying(before)));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('<stage>'));
  });

  test('a branch carrying no such file is refused, naming what should have written it', () async {
    final CheckResult answer = await step.check(held(FakeFiles(<String, String>{})));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains(map));
  });

  test('the undo puts back exactly what stood there', () async {
    final FakeFiles files = carrying(before);
    final String? captured = await step.capture(held(files));

    await step.apply(held(files));
    expect(files.contents['$repository/$map'], isNot(before));

    await step.undo(held(files), captured);
    expect(files.contents['$repository/$map'], before);
  });
}
