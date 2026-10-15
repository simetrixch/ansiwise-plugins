import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

/// Whether one named object stands in the cluster, and that it refuses what its sibling refuses.
void main() {
  final KubernetesObjectPresent deployment = KubernetesObjectPresent.fromArguments(
    const Arguments(<String, Object>{
      'kind': 'deployment',
      'name': 'controller',
      'namespace': 'tools',
      'kubectl': <String>['wrapped', 'kubectl'],
      'kubectl_needs_root': true,
    }),
  );
  const String asking =
      'wrapped kubectl -n tools get deployment controller --ignore-not-found -o name';

  PredicateContext on(FakeShell shell) => PredicateContext(
    shell: shell,
    files: FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    log: const _Quiet(),
  );

  test('holds where the object stands', () async {
    final FakeShell shell = FakeShell()..answers(asking, 'deployment.apps/controller\n');

    final PredicateResult result = await deployment.evaluate(on(shell));

    expect(result.held, isTrue);
    expect(result.because, contains('controller'));
    expect(shell.commands.single.observes, isTrue);
    expect(shell.commands.single.elevated, isTrue);
  });

  test('does not hold where the cluster answers that no such object stands', () async {
    final FakeShell shell = FakeShell()..answers(asking, '');

    expect((await deployment.evaluate(on(shell))).held, isFalse);
  });

  test('does not hold where the cluster serves no such kind', () async {
    final FakeShell shell = FakeShell()
      ..fails(asking, stderr: 'error: the server doesn\'t have a resource type "deployment"\n');

    expect((await deployment.evaluate(on(shell))).held, isFalse);
  });

  test('an unreachable cluster stops the run instead of reading as either', () async {
    final FakeShell shell = FakeShell()
      ..fails(asking, stderr: 'The connection to the server 127.0.0.1:16443 was refused\n');

    await expectLater(deployment.evaluate(on(shell)), throwsA(isA<ConditionUnanswerable>()));
  });

  test('the registry carries it beside its sibling, taking the same arguments', () {
    final RegisteredPredicate? registered =
        kubernetesRegistry.predicates[const PredicateName('kubernetes_object_present')];

    expect(registered, isNotNull);
    expect(
      registered!.arguments.map((ArgumentSpec spec) => spec.name),
      KubernetesObjectAbsent.arguments.map((ArgumentSpec spec) => spec.name),
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
