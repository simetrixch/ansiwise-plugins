import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// A cluster that could not be ASKED is not a cluster that holds nothing.
///
/// **The shape.** `kubectl get <kind> <name>` exits one for an object that is not there and exits
/// one for a cluster that never answered — no route to the API server, no credential, a client
/// refused. Six steps of this package read the second as the first, and each of them decided
/// something on it: "there is no pool, so there is none to delete", "there is no issuer to take
/// away" on a row an operator reaches by ASKING for a rebuild, "there is nothing to patch", and
/// three captures reading "this run created it" that send an undo to delete an object the cluster
/// was already running on.
///
/// **When it happens is not a corner.** The rows this matters most for are the ones that run
/// straight after a cluster comes up, which is precisely the moment an API server does not answer.
///
/// **What tells the two apart is a LIST, on the exit code alone.** `get <kind>` over a cluster
/// holding none of them writes nothing and exits ZERO — absence is not an error for a list — while
/// a cluster that cannot be reached exits non-zero. So every case below breaks BOTH readings, and
/// every innocent case beside it breaks only the get and lets the list answer, which is the state
/// each refusal must never swallow.
void main() {
  const StepName under = StepName('under_test');

  /// A cluster that answers nothing at all: the get fails and so does the list beside it.
  ClusterMachine unreachable(String kind, {String? namespace}) => ClusterMachine()
    ..cannotBeReached(
      kind,
      namespace: namespace,
      stderr: 'The connection to the server 10.0.0.1:16443 was refused',
    );

  /// A cluster that ANSWERS and holds no such object: the get fails, the list is empty at exit zero.
  ClusterMachine holdingNone(String kind, {String? namespace}) => ClusterMachine()
    ..holdingNo(
      kind,
      namespace: namespace,
      stderr: 'Error from server (NotFound): $kind not found',
    );

  group('the address pool a cluster is running on', () {
    const RemoveDefaultIpv4Ippool step = RemoveDefaultIpv4Ippool(
      podCidr: '10.4.0.0/16',
      manifestPath: '/etc/network/pod-network.yaml',
    );

    test('THE PLANTED DEFECT: a cluster that would not answer is not a cluster with no pool', () async {
      // deploy-cluster runs this row immediately after the cluster comes up, and reported "there is
      // no default-ipv4-ippool, so there is none to delete" over an API server that never answered.
      // The pod-network conversion then silently did not happen and the row stood proven.
      final ClusterMachine machine = unreachable('ippool');

      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Blocked>(), reason: '$answer');
      expect(machine.changing, isEmpty);
    });

    test('THE INNOCENT CASE: a cluster that answers and holds no pool is satisfied', () async {
      final ClusterMachine machine = holdingNone('ippool');

      final CheckResult answer = await step.check(machine.contextFor(under));

      expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
    });
  });

  group('the certificate issuer an operator asked to rebuild', () {
    const RemoveExistingClusterIssuer removing = RemoveExistingClusterIssuer(
      name: 'my-issuer',
      force: true,
    );

    test(
      'THE PLANTED DEFECT: a rebuild is not reported done over a cluster nobody asked',
      () async {
        final ClusterMachine machine = unreachable('clusterissuer');

        final CheckResult answer = await removing.check(machine.contextFor(under));

        expect(answer, isA<Blocked>(), reason: '$answer');
        expect(machine.changing, isEmpty);
      },
    );

    test('THE INNOCENT CASE: a cluster that answers and holds no issuer is satisfied', () async {
      final ClusterMachine machine = holdingNone('clusterissuer');

      final CheckResult answer = await removing.check(machine.contextFor(under));

      expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
    });

    test('THE PLANTED DEFECT: an undo leaves an issuer it could not read alone', () async {
      // capture answered null for a cluster it could not ask, and null is what tells the undo this
      // run created the issuer - so the clean-up after some OTHER step failed deleted the issuer
      // every certificate on the cluster is issued by.
      const ApplyClusterIssuer applying = ApplyClusterIssuer(
        name: 'my-issuer',
        manifestPath: '/etc/certificates/issuer.yaml',
      );
      final ClusterMachine machine = unreachable('clusterissuer');
      final StepContext context = machine.contextFor(under);

      final ClusterIssuerBefore captured = await applying.capture(context);
      await applying.undo(context, captured);

      expect(captured.unmeasured, isTrue, reason: 'a reading nobody took is not an absent issuer');
      expect(machine.changing, isEmpty, reason: 'the undo deleted an issuer it never measured');
      expect(machine.said.join('\n'), contains('could not be read'));
    });

    test('THE INNOCENT CASE: an issuer this run really created is deleted again', () async {
      const ApplyClusterIssuer applying = ApplyClusterIssuer(
        name: 'my-issuer',
        manifestPath: '/etc/certificates/issuer.yaml',
      );
      final ClusterMachine machine = holdingNone('clusterissuer');
      final StepContext context = machine.contextFor(under);

      final ClusterIssuerBefore captured = await applying.capture(context);
      await applying.undo(context, captured);

      expect(captured.unmeasured, isFalse);
      expect(machine.changing.single, contains('delete clusterissuer my-issuer'));
    });
  });

  group('the workload a program patches', () {
    const PatchContainerArgumentsAndPorts step = PatchContainerArgumentsAndPorts(
      namespace: 'kube-system',
      kind: 'deployment',
      name: 'coredns',
      container: 'coredns',
      containerArguments: <String>['-conf', '/etc/coredns/Corefile'],
      ports: <String>[],
      rolloutTimeoutSeconds: 120,
    );

    test(
      'THE PLANTED DEFECT: a cluster that would not answer is not one without the workload',
      () async {
        // "there is no deployment coredns in kube-system, so what installs it is not up and there is
        // nothing to patch" - a sentence about a cluster nobody managed to ask.
        final ClusterMachine machine = unreachable('deployment', namespace: 'kube-system');

        final CheckResult answer = await step.check(machine.contextFor(under));

        expect(answer, isA<Blocked>(), reason: '$answer');
        expect(machine.changing, isEmpty);
      },
    );

    test(
      'THE INNOCENT CASE: a cluster that answers and holds no such workload is satisfied',
      () async {
        final ClusterMachine machine = holdingNone('deployment', namespace: 'kube-system');

        final CheckResult answer = await step.check(machine.contextFor(under));

        expect(answer, isA<Satisfied>(), reason: answer is Blocked ? answer.reason : '$answer');
      },
    );
  });

  group('the cluster-wide grant a binding makes', () {
    const OidcAdminsBinding step = OidcAdminsBinding(
      name: 'oidc-admins',
      group: 'platform-admins',
      groupsPrefix: 'oidc:',
      clusterRole: 'cluster-admin',
    );

    test('THE PLANTED DEFECT: an undo leaves a binding it could not read alone', () async {
      // capture answered "the cluster did not hold it", which is the branch that deletes it - so a
      // clean-up took away a cluster-wide grant that was standing before this run started.
      final ClusterMachine machine = unreachable('clusterrolebinding');
      final StepContext context = machine.contextFor(under);

      final bool captured = await step.capture(context);
      await step.undo(context, captured);

      expect(captured, isTrue, reason: 'a reading nobody took is not an absent binding');
      expect(machine.changing, isEmpty, reason: 'the undo deleted a grant it never measured');
      expect(machine.said.join('\n'), contains('could not be read'));
    });

    test('THE INNOCENT CASE: a binding this run really made is deleted again', () async {
      final ClusterMachine machine = holdingNone('clusterrolebinding');
      final StepContext context = machine.contextFor(under);

      final bool captured = await step.capture(context);
      await step.undo(context, captured);

      expect(captured, isFalse);
      expect(machine.changing.single, contains('delete clusterrolebinding oidc-admins'));
    });
  });

  group('the default storage class of a cluster', () {
    const SetDefaultStorageClass step = SetDefaultStorageClass(
      timeoutSeconds: 60,
      intervalSeconds: 5,
    );

    /// What the step asks to learn which class carries the mark.
    String listClasses() =>
        'kubectl get storageclass -o '
        r'jsonpath={range .items[*]}{.metadata.name}{" "}'
        '{.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class}'
        r'{"\n"}{end}';

    test('THE PLANTED DEFECT: an undo leaves a default mark it could not read alone', () async {
      // The classes could not be read, which answered as the same empty map a cluster with no
      // default does - and the undo then took the mark OFF whatever carried it.
      final ClusterMachine machine = ClusterMachine();
      machine.shell.fails(listClasses(), stderr: 'Unable to connect to the server');
      final StepContext context = machine.contextFor(under);

      final DefaultStorageClassBefore captured = await step.capture(context);
      await step.undo(context, captured);

      expect(
        captured.unmeasured,
        isTrue,
        reason:
            'a reading nobody took is not a cluster with no '
            'default',
      );
      expect(machine.changing, isEmpty, reason: 'the undo unmarked a class it never measured');
      expect(machine.said.join('\n'), contains('could not be read'));
    });

    test('THE INNOCENT CASE: a mark this run really made is taken off again', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(listClasses(), 'local-path true\n');
      final StepContext context = machine.contextFor(under);

      // Captured on a cluster that had none, which is what makes the mark this run's to take back.
      await step.undo(context, const DefaultStorageClassBefore.none());

      expect(machine.changing.single, contains('patch storageclass local-path'));
    });
  });
}
