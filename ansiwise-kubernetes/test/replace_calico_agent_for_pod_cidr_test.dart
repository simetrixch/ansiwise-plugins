import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// Replacing the network agent's pods for a new range, and the proof read off the running pods.
void main() {
  const StepName under = StepName('under_test');
  const String podCidr = '10.244.0.0/16';
  const String oldCidr = '10.1.0.0/16';

  const String readPods =
      r'kubectl -n kube-system get pods -l k8s-app=calico-node -o '
      r'jsonpath={range .items[*]}{.spec.containers[0].env'
      '[?(@.name=="${ReapplyCalicoManifest.variable}")].value}'
      r'{"\n"}{end}';
  const String rollAgent = 'kubectl -n kube-system rollout restart daemonset/calico-node';
  const String rolloutStatus =
      'kubectl -n kube-system rollout status daemonset/calico-node --timeout=120s';

  const ReplaceCalicoAgentForPodCidr step = ReplaceCalicoAgentForPodCidr(
    podCidr: podCidr,
    rolloutTimeoutSeconds: 120,
  );

  test('a cluster whose every running pod carries the range is left alone', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(readPods, '$podCidr\n$podCidr\n');

    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a pod still on another range is replaced, and the running pods prove it', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell
      ..answers(readPods, '$podCidr\n$oldCidr\n')
      ..changes(rollAgent, () {
        machine.shell.answers(readPods, '$podCidr\n$podCidr\n');
      });

    final StepContext context = machine.contextFor(under);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);
    expect(await step.check(context), isA<Satisfied>());
    expect(machine.changing, <String>[rollAgent, rolloutStatus]);
  });

  test('pods that cannot be read leave the step ready rather than satisfied', () async {
    // Unreadable is not a yes: reporting the range as converged on a cluster nothing could read
    // would end the conversion on an answer nobody measured.
    final ClusterMachine machine = ClusterMachine()..shell.fails(readPods);
    expect(await step.check(machine.contextFor(under)), isA<Ready>());
  });

  test('a rollout that reports success while a stale pod still runs is a failure', () async {
    // The reason the proof reads the pods and not the rollout's exit code: a rollout that was
    // asked for and never completed reports the same zero as one that did.
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(readPods, '$podCidr\n$oldCidr\n');

    await expectLater(
      step.apply(machine.contextFor(under)),
      throwsA(
        isA<StateError>().having(
          (StateError failure) => failure.message,
          'names the stale range',
          contains(oldCidr),
        ),
      ),
    );
  });

  test('nothing read back after the rollout is a failure, not a pass', () async {
    // The steps behind this one build the pool on the assumption that every agent pod already
    // carries the range, so an answer nothing proves must not let them run.
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(readPods, '');

    await expectLater(
      step.apply(machine.contextFor(under)),
      throwsA(
        isA<StateError>().having(
          (StateError failure) => failure.message,
          'says nothing was proven',
          contains('nothing proves'),
        ),
      ),
    );
  });
}
