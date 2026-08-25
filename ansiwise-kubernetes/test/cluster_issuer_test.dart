import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The issuer every certificate on the cluster comes from: take away, apply, and the one recovery.
void main() {
  const StepName under = StepName('cluster_issuer');
  // The whole path, the way a program row states it: this package composes no base name of its
  // own, so the file the renderer writes and the file these steps apply are one value.
  const String manifestPath = '/var/lib/deploy/state/clusterissuer.yaml';
  // The names the release that installed the certificate service gave its deployments.
  const List<String> certManagerDeployments = <String>[
    'cert-manager',
    'cert-manager-webhook',
    'cert-manager-cainjector',
  ];
  // The two values the manifest DECIDES, spelled as the template writes them: one per line under
  // `acme:`. They are what the step compares, so a fixture without them would hold nothing.
  const String manifest =
      'kind: ClusterIssuer\n'
      'metadata:\n'
      '  name: my-issuer\n'
      'spec:\n'
      '  acme:\n'
      '    server: https://acme-v02.api.letsencrypt.org/directory\n'
      '    email: someone@example.test\n';
  const String issuerRegistration =
      'kubectl get clusterissuer my-issuer -o '
      r'jsonpath={.spec.acme.server}{"\n"}{.spec.acme.email}';
  const String registeredWithProduction =
      'https://acme-v02.api.letsencrypt.org/directory\nsomeone@example.test';
  const String registeredWithStaging =
      'https://acme-staging-v02.api.letsencrypt.org/directory\nsomeone@example.test';
  const String issuerReady =
      'kubectl get clusterissuer my-issuer -o '
      'jsonpath={.status.conditions[?(@.type=="Ready")].status}';
  const String issuerExists = 'kubectl get clusterissuer my-issuer -o jsonpath={.metadata.name}';

  group('taking the existing issuer away', () {
    test('happens only when that was asked for', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerExists, 'my-issuer');

      const RemoveExistingClusterIssuer left = RemoveExistingClusterIssuer(
        name: 'my-issuer',
        force: false,
      );
      expect(await left.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);

      const RemoveExistingClusterIssuer asked = RemoveExistingClusterIssuer(
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
      manifestPath: manifestPath,
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
        ..fails(issuerRegistration)
        ..changes('kubectl apply -f $manifestPath', () {
          machine.shell.answers(issuerRegistration, registeredWithProduction);
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    // WHAT THE NAME CANNOT SAY. The pair below is the whole of this step's convergence: an
    // installation that changes which authority it registers with renders a different manifest, and
    // an issuer of the right name is already standing in the cluster carrying the OLD one. Judging
    // by the name reports nothing to do and the cluster keeps issuing off the authority the
    // operator moved away from — silently, because every certificate still appears.
    test('an issuer registered with another authority is not a satisfied one', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = manifest;
      machine.shell.answers(issuerRegistration, registeredWithStaging);

      expect(
        await step.check(machine.contextFor(under)),
        isA<Ready>(),
        reason:
            'the manifest says the production authority and the cluster carries the staging one, '
            'so there is work to do however right the name looks',
      );
    });

    test('an issuer carrying exactly what the manifest says is left alone', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[manifestPath] = manifest;
      machine.shell.answers(issuerRegistration, registeredWithProduction);

      final CheckResult answer = await step.check(machine.contextFor(under));
      expect(answer, isA<Satisfied>());
      expect((answer as Satisfied).because, contains('acme-v02'));
      expect(machine.changing, isEmpty);
    });

    test('the undo removes an issuer this run created', () async {
      final ClusterMachine machine = ClusterMachine();
      await step.undo(machine.contextFor(under), const ClusterIssuerBefore.none());
      expect(machine.changing.single, contains('delete clusterissuer my-issuer'));
    });

    // AND PUTS BACK WHAT IT OVERWROTE, which is new and is the cost of the step now acting on an
    // issuer that is already there. An undo that only deleted what it created would leave the
    // cluster registered with the authority this run moved it to and call that restored.
    test('the undo puts back the registration it wrote over', () async {
      final ClusterMachine machine = ClusterMachine();
      await step.undo(
        machine.contextFor(under),
        const ClusterIssuerBefore.of((
          server: 'https://acme-staging-v02.api.letsencrypt.org/directory',
          email: 'someone@example.test',
        )),
      );

      final String patched = machine.changing.single;
      expect(patched, contains('patch clusterissuer my-issuer'));
      expect(patched, contains('acme-staging-v02'));
      expect(patched, isNot(contains('delete')));
    });
  });

  group('the one recovery an issuer that did not register gets', () {
    const RestartCertManagerAndReapplyClusterIssuer step =
        RestartCertManagerAndReapplyClusterIssuer(
          name: 'my-issuer',
          namespace: 'cert-manager',
          deployments: certManagerDeployments,
          manifestPath: manifestPath,
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
