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

  const String composeArgv =
      'kubectl create configmap app-fragments --namespace apps --from-file $fragments '
      '--dry-run=client';
  const String getArgv =
      'kubectl get configmap app-fragments --namespace apps -o json --ignore-not-found';

  /// One ConfigMap as JSON, carrying [data] and the metadata a real cluster adds of its own.
  ///
  /// The metadata is here on purpose: a resource version and a creation time change without anybody
  /// touching the object, so a check comparing the whole thing would report a difference on every
  /// run. Only the data is compared, and this is what proves it.
  String objectOf(String data, {bool live = false}) =>
      '{"apiVersion":"v1","kind":"ConfigMap",'
      '"metadata":{"name":"app-fragments","namespace":"apps"'
      '${live ? ',"resourceVersion":"84213","creationTimestamp":"2026-08-17T21:00:00Z"' : ''}},'
      '"data":$data}';

  /// A machine where the directory composes [wanted] and the cluster holds [held].
  ///
  /// [held] null stands for a cluster that has no such object at all, which `--ignore-not-found`
  /// answers as empty output rather than as a failure.
  ClusterMachine cluster({
    String wanted = '{"99-client.yaml":"version: 1"}',
    String? held = '{"99-client.yaml":"version: 1"}',
    bool askFails = false,
    Map<String, String> tree = const <String, String>{'$fragments/99-client.yaml': 'version: 1\n'},
  }) {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents.addAll(tree);
    machine.shell
      ..answers('$composeArgv -o json', objectOf(wanted))
      ..answer(
        getArgv,
        CommandResult(
          exitCode: askFails ? 1 : 0,
          stdout: askFails ? '' : (held == null ? '' : objectOf(held, live: true)),
          stderr: askFails ? 'the server could not be reached' : '',
          elapsed: Duration.zero,
        ),
      )
      ..answers('$composeArgv -o yaml', 'apiVersion: v1\nkind: ConfigMap\n');
    return machine;
  }

  group('the check', () {
    test('a directory that is not in the checkout is blocked and named', () async {
      final CheckResult result = await step.check(
        cluster(tree: const <String, String>{}).contextFor(under),
      );
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('config/fragments'));
    });

    test('a directory holding no file is blocked rather than composed', () async {
      // A ConfigMap with no keys mounts cleanly and the pod discovers nothing, which looks exactly
      // like a release that came up correctly.
      final ClusterMachine machine = cluster(tree: const <String, String>{});
      machine.files.directories.add(fragments);
      expect(await step.check(machine.contextFor(under)), isA<Blocked>());
    });

    test('the same data, whatever metadata the cluster added of its own, is finished', () async {
      expect(await step.check(cluster().contextFor(under)), isA<Satisfied>());
    });

    test('a key whose file changed is work', () async {
      expect(
        await step.check(cluster(held: '{"99-client.yaml":"version: 2"}').contextFor(under)),
        isA<Ready>(),
      );
    });

    test('A KEY THAT OUTLIVED ITS FILE is work, which is the property this exists for', () async {
      // The cluster carries a declaration nobody meant to keep. Comparing key by key, or asking
      // only whether every wanted key is present, would call this finished.
      expect(
        await step.check(
          cluster(
            held: '{"99-client.yaml":"version: 1","98-gone.yaml":"version: 1"}',
          ).contextFor(under),
        ),
        isA<Ready>(),
      );
    });

    test('an object the cluster does not have at all is work', () async {
      expect(await step.check(cluster(held: null).contextFor(under)), isA<Ready>());
    });

    test('a failure to ASK is not the same as work to do', () async {
      expect(await step.check(cluster(askFails: true).contextFor(under)), isA<Blocked>());
    });
  });

  group('the apply', () {
    test(
      'composes from the directory without sending anything, then applies what it composed',
      () async {
        final ClusterMachine machine = cluster();

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
      final ClusterMachine machine = cluster();

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
    final ClusterMachine machine = cluster();
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
