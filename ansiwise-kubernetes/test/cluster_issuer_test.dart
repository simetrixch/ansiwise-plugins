import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The issuer every certificate on the cluster comes from: take away, apply, and the one recovery.
void main() {
  const StepName under = StepName('cluster_issuer');
  const String stateDirectory = '/var/lib/deploy/state';
  const String manifestPath = '$stateDirectory/clusterissuer.yaml';
  const String manifest = 'kind: ClusterIssuer\nmetadata:\n  name: my-issuer\n';
  const String issuerReady =
      'kubectl get clusterissuer my-issuer -o '
      'jsonpath={.status.conditions[?(@.type=="Ready")].status}';
  const String issuerExists = 'kubectl get clusterissuer my-issuer -o jsonpath={.metadata.name}';

  group('taking the existing issuer away', () {
    test('happens only when that was asked for', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerExists, 'my-issuer');

      const DeleteExistingClusterIssuer left = DeleteExistingClusterIssuer(
        name: 'my-issuer',
        force: false,
      );
      expect(await left.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);

      const DeleteExistingClusterIssuer asked = DeleteExistingClusterIssuer(
        name: 'my-issuer',
        force: true,
      );
      expect(await asked.check(machine.contextFor(under)), isA<Ready>());
      expect(asked.irreversibleReason, contains('account key'));
    });
  });

  group('applying the rendered issuer', () {
    const ApplyClusterIssuer step = ApplyClusterIssuer(
      name: 'my-issuer',
      stateDirectory: stateDirectory,
    );

    test('a manifest nothing rendered is refused rather than applied', () async {
      final ClusterMachine machine = ClusterMachine();
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains(manifestPath));
    });

    test('the rendered manifest is applied and the cluster is asked afterwards', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = manifest;
      machine.shell
        ..fails(issuerExists)
        ..changes('kubectl apply -f $manifestPath', () {
          machine.shell.answers(issuerExists, 'my-issuer');
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the undo removes only an issuer this run created', () async {
      final ClusterMachine machine = ClusterMachine();
      await step.undo(machine.contextFor(under), true);
      expect(machine.changing, isEmpty);

      await step.undo(machine.contextFor(under), false);
      expect(machine.changing.single, contains('delete clusterissuer my-issuer'));
    });
  });

  group('the one recovery an issuer that did not register gets', () {
    const RestartCertManagerAndReapplyClusterIssuer step =
        RestartCertManagerAndReapplyClusterIssuer(
          name: 'my-issuer',
          namespace: 'cert-manager',
          stateDirectory: stateDirectory,
          settleSeconds: 15,
          waitSeconds: 60,
          intervalSeconds: 10,
        );

    test('a freshly applied issuer with no status at all reports as not ready', () async {
      // A reader that expects the conditions to be there fails on the very state it is meant to
      // report.
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '');
      expect(
        await RestartCertManagerAndReapplyClusterIssuer.isReady(
          machine.contextFor(under),
          const Kubectl(),
          'my-issuer',
        ),
        isFalse,
      );
    });

    test('an issuer that registered is left completely alone', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, 'True');
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the recovery restarts the service and applies the issuer again, in that order', () async {
      // Polling longer does not converge: what it is stuck on is network state the certificate
      // service is holding from before the cluster's own network was finished.
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = manifest;
      machine.shell
        ..answers(issuerReady, '')
        ..changes('kubectl apply -f $manifestPath', () {
          machine.shell.answers(issuerReady, 'True');
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final List<String> ran = machine.changing;
      expect(ran.first, contains('rollout restart deployment/cert-manager'));
      expect(
        ran.indexWhere((String each) => each.contains('delete clusterissuer')),
        lessThan(ran.indexWhere((String each) => each.contains('apply -f'))),
      );
      expect(machine.clock.elapsed.inSeconds, greaterThanOrEqualTo(20));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the budget ends here, and what it means is reported', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = manifest;
      machine.shell.answers(issuerReady, '');

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.message,
            'message',
            contains('stuck rather than slow'),
          ),
        ),
      );
    });
  });
}
