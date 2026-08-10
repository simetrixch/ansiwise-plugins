import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// The ConfigMap the identity provider's blueprints reach the cluster in.
///
/// Two properties decide it, and both fail silently. A directory nobody read leaves the release
/// mounting an empty overlay, which comes up green and offers a login to nothing. And a key that
/// outlives the file it came from is an OIDC client this installation still offers that nobody
/// meant to keep.
void main() {
  const KubernetesConfigmapFromDirectory step = KubernetesConfigmapFromDirectory(
    repository: '/srv/hostyour-cloud',
    directory: 'bootstrap/idp/blueprints',
    name: 'idp-blueprints',
    namespace: 'idp',
    staging: '/run/ansiwise',
  );
  const String blueprints = '/srv/hostyour-cloud/bootstrap/idp/blueprints';
  const String composed = '/run/ansiwise/idp-idp-blueprints.yaml';

  ({StepContext context, FakeFiles files}) contextOn(
    FakeShell shell, {
    Map<String, String> tree = const <String, String>{'$blueprints/99-argocd.yaml': 'version: 1\n'},
  }) {
    final FakeFiles files = FakeFiles(<String, String>{...tree});
    return (
      context: StepContext(
        shell: shell,
        files: files,
        http: FakeHttp(),
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const _SaysNothing(),
        step: const StepName('kubernetes_configmap_from_directory'),
        arguments: Arguments.none,
        facts: Facts.none,
      ),
      files: files,
    );
  }

  FakeShell diffing(int exitCode) => FakeShell(<String, CommandResult>{
    'microk8s kubectl diff --filename $composed': CommandResult(
      exitCode: exitCode,
      stdout: '',
      stderr: exitCode > 1 ? 'the server could not be reached' : '',
      elapsed: Duration.zero,
    ),
    'microk8s kubectl create configmap idp-blueprints --namespace idp --from-file $blueprints '
        '--dry-run=client -o yaml': const CommandResult(
      exitCode: 0,
      stdout: 'apiVersion: v1\nkind: ConfigMap\n',
      stderr: '',
      elapsed: Duration.zero,
    ),
  });

  group('the check', () {
    test('a directory that is not in the checkout is blocked and named', () async {
      final CheckResult result = await step.check(
        contextOn(diffing(1), tree: const <String, String>{}).context,
      );
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('bootstrap/idp/blueprints'));
    });

    test('a directory holding no file is blocked rather than composed', () async {
      // A ConfigMap with no keys mounts cleanly and the worker discovers nothing, which looks
      // exactly like a release that came up correctly and offers a login to no client at all.
      final FakeFiles empty = FakeFiles();
      empty.directories.add(blueprints);
      final CheckResult result = await step.check(
        StepContext(
          shell: diffing(1),
          files: empty,
          http: FakeHttp(),
          clock: FakeClock(),
          entropy: FakeEntropy(),
          log: const _SaysNothing(),
          step: const StepName('kubernetes_configmap_from_directory'),
          arguments: Arguments.none,
          facts: Facts.none,
        ),
      );
      expect(result, isA<Blocked>());
    });

    test('no difference is what it is finished against', () async {
      expect(await step.check(contextOn(diffing(0)).context), isA<Satisfied>());
    });

    test('a difference is work', () async {
      expect(await step.check(contextOn(diffing(1)).context), isA<Ready>());
    });

    test('a failure to ASK is not the same as work to do', () async {
      expect(await step.check(contextOn(diffing(2)).context), isA<Blocked>());
    });
  });

  group('the apply', () {
    test(
      'composes from the directory without sending anything, then applies what it composed',
      () async {
        final FakeShell shell = diffing(1);
        final ({StepContext context, FakeFiles files}) it = contextOn(shell);

        await step.apply(it.context);

        expect(shell.commands.first.argv, contains('--dry-run=client'));
        expect(shell.commands.first.argv, contains(blueprints));
        expect(shell.commands.last.argv, <String>[
          'microk8s',
          'kubectl',
          'apply',
          '--filename',
          composed,
        ]);
      },
    );

    test('the composed object does not stay on the machine', () async {
      final FakeShell shell = diffing(1);
      final ({StepContext context, FakeFiles files}) it = contextOn(shell);

      await step.apply(it.context);

      expect(await it.files.exists(composed), isFalse);
    });

    test('a create that fails is a failure, and nothing is applied after it', () async {
      final FakeShell shell = FakeShell(<String, CommandResult>{
        'microk8s kubectl create configmap idp-blueprints --namespace idp --from-file $blueprints '
            '--dry-run=client -o yaml': const CommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'error: error reading',
          elapsed: Duration.zero,
        ),
      });
      final ({StepContext context, FakeFiles files}) it = contextOn(shell);

      await expectLater(step.apply(it.context), throwsA(isA<CommandFailed>()));
      expect(
        shell.commands.where((Command one) => one.argv.contains('apply')),
        isEmpty,
        reason: 'nothing was applied from an object that was never composed',
      );
    });
  });

  test('the undo removes the map and tolerates it being gone', () async {
    // False is what the capture answers for a namespace that did not already carry the ConfigMap,
    // which is the only case where taking the run back means deleting it. Passed rather than
    // captured so the single command below is the delete and not a `kubectl get` in front of it.
    final FakeShell shell = diffing(0);
    await step.undo(contextOn(shell).context, false);
    expect(shell.commands.single.argv, <String>[
      'microk8s',
      'kubectl',
      'delete',
      'configmap',
      'idp-blueprints',
      '--namespace',
      'idp',
      '--ignore-not-found',
    ]);
  });
}

/// A log for a test that has to build a context and has nothing to say in it.
final class _SaysNothing implements Logger {
  const _SaysNothing();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
