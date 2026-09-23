import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';
import 'package:test/test.dart';

import 'git_checkout.dart';

/// A key that stands INSIDE a block, and the failure this shape exists to end.
///
/// THE PLANTED CASE IS THE ONE THAT HAPPENED. Matching a key only at the head of a line leaves a
/// file carrying it under `global:` unmatched, and the write appends a SECOND key at the head of
/// the file. Measured on a real machine — a values file carried `clusterIssuer` twice, nested with
/// the old value and at the top with the new one, every chart went on reading the old, and the run
/// was green. So the cases below check not only that the right line changes but that no second one
/// appears.
void main() {
  const String file = 'clusters/platform/values-common.yaml';
  const String wanted = 'platform-acme';

  const WriteValueInBranchFile step = WriteValueInBranchFile(
    repository: repository,
    path: file,
    key: 'global.clusterIssuer',
    valueAnswer: 'cluster_issuer',
    fileMode: 420,
  );

  FakeShell onBranch() =>
      FakeShell()..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$branch\n');

  FakeFiles carrying(String contents) => FakeFiles(<String, String>{'$repository/$file': contents});

  StepContext held(FakeFiles files) => contextOn(
    shell: onBranch(),
    files: files,
    name: branch,
    also: const <String, Object>{'cluster_issuer': wanted},
  );

  String written(FakeFiles files) => files.contents['$repository/$file']!;

  const String nested =
      '# the chain every chart reads\n'
      'global:\n'
      '  domain: example.invalid\n'
      '  clusterIssuer: platform-local\n'
      '  stage: prod\n'
      'other:\n'
      '  clusterIssuer: something-else\n';

  test('THE INNOCENT CASE: the nested line changes, in place and at its own indentation', () async {
    final FakeFiles files = carrying(nested);

    expect(await step.check(held(files)), isA<Ready>());
    await step.apply(held(files));

    expect(written(files), contains('  clusterIssuer: $wanted\n'));
    expect(
      await step.check(held(files)),
      isA<Satisfied>(),
      reason: 'a second run over the same file has nothing to do',
    );
  });

  test('THE PLANTED CASE: no second key appears at the head of the file', () async {
    final FakeFiles files = carrying(nested);
    await step.apply(held(files));

    expect(
      written(files).split('\n').where((String l) => l.startsWith('clusterIssuer:')),
      isEmpty,
      reason: 'appending here is what made a file say the same thing twice with two values',
    );
  });

  test('a key of the same name in ANOTHER block is left alone', () async {
    final FakeFiles files = carrying(nested);
    await step.apply(held(files));

    expect(
      written(files),
      contains('  clusterIssuer: something-else\n'),
      reason: 'the path names one block, and only that block',
    );
  });

  test('a path whose block is absent refuses rather than inventing one', () async {
    final FakeFiles files = carrying('other:\n  clusterIssuer: something-else\n');

    expect(await step.check(held(files)), isA<Blocked>());
    await expectLater(step.apply(held(files)), throwsA(isA<StateError>()));
    expect(written(files), 'other:\n  clusterIssuer: something-else\n');
  });

  group('a key its block does not carry yet', () {
    const WriteValueInBranchFile apiHost = WriteValueInBranchFile(
      repository: repository,
      path: file,
      key: 'global.apiHost',
      value: '100.64.0.1',
      fileMode: 420,
    );

    test(
      'is inserted directly under the block\'s line, and the second run changes nothing',
      () async {
        const String map =
            'stage: prod\nrole: master\n\nglobal:\n  domain: m1.example.com\n  clusterName: m1\n';
        const String gained =
            'stage: prod\nrole: master\n\nglobal:\n  apiHost: 100.64.0.1\n'
            '  domain: m1.example.com\n  clusterName: m1\n';
        final FakeFiles files = carrying(map);

        expect(await apiHost.check(held(files)), isA<Ready>());
        expect(((await apiHost.plan(held(files))) as DiffPlan).after, gained);
        await apiHost.apply(held(files));
        expect(written(files), gained);

        expect(await apiHost.check(held(files)), isA<Satisfied>());
        await apiHost.apply(held(files));
        expect(written(files), gained);
      },
    );

    test('goes two deeper than the block\'s line where the block holds nothing yet', () async {
      final FakeFiles files = carrying('stage: prod\nglobal:\nrole: master\n');

      await apiHost.apply(held(files));

      expect(written(files), 'stage: prod\nglobal:\n  apiHost: 100.64.0.1\nrole: master\n');
    });

    test('THE PLANTED CASE: a key of the same name deeper inside the block is not it', () async {
      // Taken for the key, the deeper line would be overwritten and the block would still lack its
      // own — while the check reported the value recorded.
      const String deeper =
          'global:\n  endpoints:\n    tailnet:\n      apiHost: 100.64.0.9\n  domain: m1.example.com\n';
      final FakeFiles files = carrying(deeper);

      expect(await apiHost.check(held(files)), isA<Ready>());
      await apiHost.apply(held(files));

      expect(written(files), deeper.replaceFirst('global:\n', 'global:\n  apiHost: 100.64.0.1\n'));
    });

    test('is refused where the block\'s line holds a value or a list rather than keys', () async {
      for (final String shape in <String>['global: {}\n', 'global:\n  - m1\n', 'global:\n- m1\n']) {
        final FakeFiles files = carrying(shape);

        expect(await apiHost.check(held(files)), isA<Blocked>(), reason: shape);
        await expectLater(apiHost.apply(held(files)), throwsA(isA<StateError>()));
        expect(written(files), shape);
      }
    });
  });

  test('THE INNOCENT NEIGHBOUR: a key with no dot still stands at the head of the file', () async {
    const WriteValueInBranchFile flat = WriteValueInBranchFile(
      repository: repository,
      path: file,
      key: 'release',
      valueAnswer: 'cluster_issuer',
      fileMode: 420,
    );
    final FakeFiles files = carrying('fqdn: $branch\nrelease:\n');

    await flat.apply(held(files));

    expect(written(files), contains('release: $wanted'));
  });
  test('THE INNOCENT NEIGHBOUR: applying to a file that already says it does not refuse', () async {
    // The refusal above asks whether the LINE is there, never whether the contents changed - a file
    // already carrying the wanted value changes by nothing either, and that one is finished.
    final FakeFiles files = carrying(nested.replaceAll('platform-local', wanted));

    await step.apply(held(files));

    expect(written(files), contains('  clusterIssuer: $wanted'));
  });
}
