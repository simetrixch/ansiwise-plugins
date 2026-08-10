import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The ConfigMap a directory of files reaches the cluster in.
///
/// Two properties decide it, and both fail silently. A directory nobody read leaves the release
/// mounting an empty overlay, which comes up green and discovers nothing. And a key that outlives
/// the file it came from is a declaration this cluster still carries that nobody meant to keep.
void main() {
  const StepName under = StepName('kubernetes_configmap_from_directory');
  const KubernetesConfigmapFromDirectory step = KubernetesConfigmapFromDirectory(
    repository: '/srv/checkout',
    directory: 'config/fragments',
    name: 'app-fragments',
    namespace: 'apps',
    staging: '/run/staging',
  );
  const String fragments = '/srv/checkout/config/fragments';
  const String composed = '/run/staging/apps-app-fragments.yaml';

  /// A machine whose `kubectl diff` exits with [exitCode] and whose compose succeeds.
  ClusterMachine diffing(
    int exitCode, {
    Map<String, String> tree = const <String, String>{'$fragments/99-client.yaml': 'version: 1\n'},
  }) {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents.addAll(tree);
    machine.shell
      ..answer(
        'kubectl diff --filename $composed',
        CommandResult(
          exitCode: exitCode,
          stdout: '',
          stderr: exitCode > 1 ? 'the server could not be reached' : '',
          elapsed: Duration.zero,
        ),
      )
      ..answers(
        'kubectl create configmap app-fragments --namespace apps --from-file $fragments '
            '--dry-run=client -o yaml',
        'apiVersion: v1\nkind: ConfigMap\n',
      );
    return machine;
  }

  group('the check', () {
    test('a directory that is not in the checkout is blocked and named', () async {
      final CheckResult result = await step.check(
        diffing(1, tree: const <String, String>{}).contextFor(under),
      );
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('config/fragments'));
    });

    test('a directory holding no file is blocked rather than composed', () async {
      // A ConfigMap with no keys mounts cleanly and the pod discovers nothing, which looks exactly
      // like a release that came up correctly.
      final ClusterMachine machine = diffing(1, tree: const <String, String>{});
      machine.files.directories.add(fragments);
      expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    });

    test('no difference is what it is finished against', () async {
      expect(await step.check(diffing(0).contextFor(under)), isA<Satisfied>());
    });

    test('a difference is work', () async {
      expect(await step.check(diffing(1).contextFor(under)), isA<Ready>());
    });

    test('a failure to ASK is not the same as work to do', () async {
      expect(await step.check(diffing(2).contextFor(under)), isA<Blocked>());
    });
  });

  group('the apply', () {
    test(
      'composes from the directory without sending anything, then applies what it composed',
      () async {
        final ClusterMachine machine = diffing(1);

        await step.apply(machine.contextFor(under));

        expect(machine.shell.commands.first.argv, contains('--dry-run=client'));
        expect(machine.shell.commands.first.argv, contains(fragments));
        expect(machine.shell.commands.last.argv, <String>[
          'kubectl',
          'apply',
          '--filename',
          composed,
        ]);
      },
    );

    test('the composed object does not stay on the machine', () async {
      final ClusterMachine machine = diffing(1);

      await step.apply(machine.contextFor(under));

      expect(await machine.files.exists(composed), isFalse);
    });

    test('a create that fails is a failure, and nothing is applied after it', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents['$fragments/99-client.yaml'] = 'version: 1\n';
      machine.shell.answer(
        'kubectl create configmap app-fragments --namespace apps --from-file $fragments '
        '--dry-run=client -o yaml',
        const CommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'error: error reading',
          elapsed: Duration.zero,
        ),
      );

      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(
        machine.shell.commands.where((Command one) => one.argv.contains('apply')),
        isEmpty,
        reason: 'nothing was applied from an object that was never composed',
      );
    });
  });

  test('the undo removes the map and tolerates it being gone', () async {
    // False is what the capture answers for a namespace that did not already carry the ConfigMap,
    // which is the only case where taking the run back means deleting it. Passed rather than
    // captured so the single command below is the delete and not a `kubectl get` in front of it.
    final ClusterMachine machine = diffing(0);
    await step.undo(machine.contextFor(under), false);
    expect(machine.shell.commands.single.argv, <String>[
      'kubectl',
      'delete',
      'configmap',
      'app-fragments',
      '--namespace',
      'apps',
      '--ignore-not-found',
    ]);
  });
}
