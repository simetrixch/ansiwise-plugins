import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The binding that gives an identity provider's administrator group its cluster rights.
void main() {
  const StepName under = StepName('oidc_admins_binding');
  const OidcAdminsBinding step = OidcAdminsBinding(
    name: 'oidc-platform-admins',
    group: 'Admins',
    groupsPrefix: 'oidc:',
    clusterRole: 'cluster-admin',
  );

  test('the binding carries the prefix the API server adds', () async {
    // The cluster never sees the group the identity provider issued, only the prefixed name — a
    // binding written without the prefix matches nobody.
    final ClusterMachine machine = ClusterMachine();
    machine.shell.fails('kubectl get clusterrolebinding oidc-platform-admins -o json');

    final StepContext context = machine.contextFor(under);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(machine.changing.join('\n'), contains('--group=oidc:Admins'));
  });

  test('a binding holding the prefixed group under the role is finished work', () async {
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(
      'kubectl get clusterrolebinding oidc-platform-admins -o json',
      '{"roleRef":{"name":"cluster-admin"},'
          '"subjects":[{"kind":"Group","name":"oidc:Admins"}]}',
    );
    expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    expect(machine.changing, isEmpty);
  });

  test('a binding whose role drifted is replaced, delete first', () async {
    // A binding cannot be edited into the right shape by a create, and the parts that drift are
    // the parts that decide who holds cluster-wide rights.
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(
      'kubectl get clusterrolebinding oidc-platform-admins -o json',
      '{"roleRef":{"name":"view"},"subjects":[{"kind":"Group","name":"oidc:Admins"}]}',
    );

    final StepContext context = machine.contextFor(under);
    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(machine.changing.first, contains('delete clusterrolebinding oidc-platform-admins'));
    expect(machine.changing.last, contains('create clusterrolebinding oidc-platform-admins'));
  });

  test('the undo removes only a binding this run created', () async {
    final ClusterMachine machine = ClusterMachine();
    await step.undo(machine.contextFor(under), true);
    expect(machine.changing, isEmpty, reason: 'the name was taken before this run started');

    await step.undo(machine.contextFor(under), false);
    expect(machine.changing.single, contains('delete clusterrolebinding oidc-platform-admins'));
  });
}
