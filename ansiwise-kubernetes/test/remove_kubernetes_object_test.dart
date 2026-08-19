import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The guarded removal, and the one defect it exists to make unwritable: deleting an object that
/// merely SHARES A NAME with the one an earlier run created. The label is the mark, and an object
/// without it is refused, never removed.
void main() {
  const StepName under = StepName('remove_kubernetes_object');
  const RemoveKubernetesObject step = RemoveKubernetesObject(
    repository: '/srv/scratch',
    manifest: 'own-project.yaml',
    ownerLabel: 'example.com/managed',
    ownerLabelValue: 'true',
  );
  const String path = '/srv/scratch/own-project.yaml';
  const String getKey = 'kubectl get --filename $path -o json';

  ClusterMachine holding(String? liveObject) {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[path] = 'kind: AppProject\n';
    if (liveObject == null) {
      machine.shell.fails(getKey, stderr: 'not found');
    } else {
      machine.shell.answers(getKey, liveObject);
    }
    return machine;
  }

  test('a cluster holding none of the objects is already removed', () async {
    expect(await step.check(holding(null).contextFor(under)), isA<Satisfied>());
  });

  test('an object WITHOUT the label is refused by name — a collision, not a target', () async {
    // The planted defect: the platform's own object of the same name, made by something else. An
    // unguarded delete would take it away and nothing would say why everything behind it broke.
    final ClusterMachine machine = holding(
      '{"kind":"AppProject","metadata":{"name":"s1","labels":{"other":"true"}}}',
    );
    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('AppProject "s1"'));
    expect((answer).reason, contains('refuses a name collision'));
  });

  test('a labeled object is work, and the apply deletes by the manifest', () async {
    final ClusterMachine machine = holding(
      '{"kind":"AppProject","metadata":{"name":"s1",'
      '"labels":{"example.com/managed":"true"}}}',
    );
    final StepContext context = machine.contextFor(under);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(machine.changing, <String>['kubectl delete --filename $path --ignore-not-found']);
  });

  test('a LIST of objects is judged whole — one unmarked member refuses the manifest', () async {
    final ClusterMachine machine = holding(
      '{"kind":"List","items":['
      '{"kind":"AppProject","metadata":{"name":"a","labels":{"example.com/managed":"true"}}},'
      '{"kind":"AppProject","metadata":{"name":"b","labels":{}}}]}',
    );
    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('"b"'));
  });

  test('a listing nobody can read never passes for "all marked"', () async {
    final ClusterMachine machine = holding('this is not json');
    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(answer, isA<Blocked>());
  });

  test('a manifest the checkout does not carry is blocked and named', () async {
    final ClusterMachine machine = ClusterMachine();
    final CheckResult answer = await step.check(machine.contextFor(under));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('own-project.yaml'));
  });
}
