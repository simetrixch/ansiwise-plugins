import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

/// Whether one named object is absent from the cluster, and what the condition refuses to answer.
void main() {
  const KubernetesObjectAbsent deployment = KubernetesObjectAbsent(
    kind: 'deployment',
    name: 'controller',
    namespace: 'tools',
    kubectl: Kubectl(<String>['wrapped', 'kubectl'], true),
  );
  const KubernetesObjectAbsent clusterScoped = KubernetesObjectAbsent(
    kind: 'clusterissuer',
    name: 'platform-acme',
  );

  const String asking =
      'wrapped kubectl -n tools get deployment controller --ignore-not-found -o name';
  const String askingClusterScoped =
      'kubectl get clusterissuer platform-acme --ignore-not-found -o name';

  PredicateContext on(FakeShell shell) => PredicateContext(
    shell: shell,
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    log: const _Quiet(),
  );

  test('holds where the cluster answers that no such object stands', () async {
    final FakeShell shell = FakeShell()..answers(asking, '');

    final PredicateResult result = await deployment.evaluate(on(shell));

    expect(result.held, isTrue);
    expect(result.because, contains('controller'));
  });

  test('does not hold where the object stands', () async {
    final FakeShell shell = FakeShell()..answers(asking, 'deployment.apps/controller\n');

    expect((await deployment.evaluate(on(shell))).held, isFalse);
  });

  test('a cluster-scoped object is asked for without a namespace', () async {
    final FakeShell shell = FakeShell()
      ..answers(askingClusterScoped, 'clusterissuer.cert-manager.io/platform-acme\n');

    expect((await clusterScoped.evaluate(on(shell))).held, isFalse);
    expect(shell.ran, <String>[askingClusterScoped]);
  });

  test('holds where the cluster serves no such kind, since no object of it can stand', () async {
    final FakeShell shell = FakeShell()
      ..fails(
        askingClusterScoped,
        stderr: 'error: the server doesn\'t have a resource type "clusterissuer"\n',
      );

    final PredicateResult result = await clusterScoped.evaluate(on(shell));

    expect(result.held, isTrue);
    expect(result.because, contains('clusterissuer'));
  });

  test('an unreachable cluster stops the run instead of reading as absent', () async {
    final FakeShell shell = FakeShell()
      ..fails(
        asking,
        stderr:
            'The connection to the server 127.0.0.1:16443 was refused - did you specify the '
            'right host or port?\n',
      );

    await expectLater(
      deployment.evaluate(on(shell)),
      throwsA(
        isA<ConditionUnanswerable>().having(
          (ConditionUnanswerable refusal) => refusal.toString(),
          'refusal',
          allOf(contains('controller'), contains('was refused')),
        ),
      ),
    );
  });

  test('a refused credential stops the run too', () async {
    final FakeShell shell = FakeShell()
      ..fails(asking, stderr: 'Error from server (Forbidden): deployments.apps is forbidden\n');

    await expectLater(deployment.evaluate(on(shell)), throwsA(isA<ConditionUnanswerable>()));
  });

  test('an answer naming some other object is not read as either', () async {
    // A wrapped client refused at exit zero writes its refusal where the object's name would be.
    final FakeShell shell = FakeShell()..answers(asking, 'insufficient permissions\n');

    await expectLater(deployment.evaluate(on(shell)), throwsA(isA<ConditionUnanswerable>()));
  });

  test('it only looks, as root where the invocation says so', () async {
    final FakeShell shell = FakeShell()..answers(asking, '');
    await deployment.evaluate(on(shell));

    expect(shell.commands.single.observes, isTrue);
    expect(shell.commands.single.elevated, isTrue);
  });

  test('the registry carries it under its name, taking kind, name and namespace', () {
    final RegisteredPredicate? registered =
        kubernetesRegistry.predicates[const PredicateName('kubernetes_object_absent')];

    expect(registered, isNotNull);
    expect(
      registered!.arguments.map((ArgumentSpec spec) => spec.name),
      containsAll(<String>['kind', 'name', 'namespace', 'kubectl', 'kubectl_needs_root']),
    );
  });
}

/// A log nobody reads.
final class _Quiet implements Logger {
  const _Quiet();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
