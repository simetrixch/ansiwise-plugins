import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// Putting the authority a cluster issues from into the machine's own trust store, and the one
/// property everything here circles: the step is satisfied by what the MACHINE trusts, never by
/// where a file was put.
///
/// FIVE CASES, THE INNOCENT ONE FIRST. A machine that ends up trusting the authority; a second run
/// over the same state; the authority rotated under a file that is still there; the file placed
/// while the bundle does not carry it; and a Secret the certificate service has not written yet.
/// The fourth is the planted case — a step satisfied on the file alone reports a machine as
/// trusting something it refuses, and every https row against this cluster then fails somewhere
/// else, as a network fault.
void main() {
  const StepName under = StepName('trust_cluster_authority');
  const String root = '-----BEGIN CERTIFICATE-----\nfixture-authority\n-----END CERTIFICATE-----\n';
  const String other =
      '-----BEGIN CERTIFICATE-----\nrotated-authority\n-----END CERTIFICATE-----\n';
  const String placed = '/usr/local/share/ca-certificates/platform-ca.crt';
  const String bundle = '/etc/ssl/certs/ca-certificates.crt';
  const String read = 'kubectl -n cert-manager get secret platform-ca -o json';

  const TrustClusterAuthority step = TrustClusterAuthority(
    namespace: 'cert-manager',
    secret: 'platform-ca',
    field: 'ca.crt',
    path: placed,
    refresh: <String>['update-ca-certificates'],
    bundlePath: bundle,
  );

  String secretHolding(String authority) => jsonEncode(<String, Object?>{
    'data': <String, String>{'ca.crt': base64Encode(utf8.encode(authority))},
  });

  /// A machine whose cluster holds [authority], and whose bundle stands as a real rebuild leaves it.
  ///
  /// THE REBUILD IS RECORDED AND NOT CARRIED OUT — a fake shell answers commands, it does not run
  /// them — so the bundle this fixture plants is the statement of what the machine looks like
  /// afterwards. [trusted] is what makes each case the case it is: the same step against a bundle
  /// that took the authority up and against one that did not.
  ClusterMachine holding(String authority, {required bool trusted}) {
    final ClusterMachine machine = ClusterMachine();
    machine.shell.answers(read, secretHolding(authority));
    machine.files.contents[bundle] = trusted
        ? '$authority<the roots this machine shipped with>\n'
        : '<the roots this machine shipped with>\n';
    return machine;
  }

  test(
    'THE INNOCENT CASE: the authority lands in the collection directory and in the bundle',
    () async {
      final ClusterMachine machine = holding(root, trusted: true);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents[placed], root);
      expect(machine.files.contents[bundle], contains(root.trim()));
      expect(
        machine.files.modes[placed],
        0x1A4,
        reason: 'a root is read by everything on the machine and is no part of a key',
      );
    },
  );

  test('a second run over the same cluster state has nothing to do', () async {
    final ClusterMachine machine = holding(root, trusted: true);
    final StepContext context = machine.contextFor(under);
    await step.apply(context);

    expect(await step.check(context), isA<Satisfied>());
  });

  test('an authority the cluster rotated makes the step work again — the check compares', () async {
    final ClusterMachine machine = holding(other, trusted: false);
    machine.files.contents[placed] = root;
    machine.files.contents[bundle] = '$root<the roots this machine shipped with>\n';

    expect(
      await step.check(machine.contextFor(under)),
      isA<Ready>(),
      reason: 'the machine trusts the old authority, and the cluster now issues from another',
    );
  });

  test('THE PLANTED CASE: the file is placed and the bundle does not carry it, and that is a '
      'failure and not a pass', () async {
    // A rebuild that runs and takes nothing up is the shape this guards: on such a machine every
    // https row against this cluster goes on being refused, and nothing here would have said so.
    final ClusterMachine machine = holding(root, trusted: false);

    await expectLater(
      step.apply(machine.contextFor(under)),
      throwsA(isA<StateError>()),
      reason: 'a machine that does not trust the authority must not be reported as trusting it',
    );
  });

  test(
    'a Secret the certificate service has not written yet is named, never read as empty',
    () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(read, '{"data":{}}');

      expect(
        await step.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'the check reports it as not ready yet rather than refusing',
      );
      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'names the Secret and the service that writes it',
            allOf(contains('platform-ca'), contains('certificate service')),
          ),
        ),
      );
    },
  );
}
