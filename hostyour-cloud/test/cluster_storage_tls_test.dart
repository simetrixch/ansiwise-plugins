import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The issuer every certificate on this cluster comes from.
///
/// Where the volumes land is a machine's business and moved to the machine plugin with the steps
/// that put them there. What stays here is the part no tool decides: which authority this product
/// asks for a certificate, and under whose mailbox it asks.
void main() {
  const StepName under = StepName('under_test');

  group('the certificate issuer', () {
    test('the mailbox is the one this run answered, whatever it reads like', () async {
      // Nothing here recognises an illustration. The address used to stand in the program file and
      // was warned about when it ended in the domain the examples use; it is answered now, so a
      // rule of that kind would only refuse an operator whose own mailbox reads like one.
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = machine.contextFor(
        under,
        Arguments.none,
        clusterAnswering(<String, Object>{'letsencrypt_email': 'ops@example.com'}),
      );

      await clusterIssuer.apply(context);

      expect(machine.files.contents[clusterIssuer.path], contains('email: ops@example.com'));
    });

    test('the rendered manifest names the issuer, the authority and how it is answered', () async {
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = machine.contextFor(under);
      await clusterIssuer.apply(context);
      final String written = machine.files.contents[clusterIssuer.path]!;
      expect(written, contains('kind: ClusterIssuer'));
      expect(written, contains('name: letsencrypt-prod'));
      expect(written, contains('server: https://acme-v02.api.letsencrypt.org/directory'));
      expect(written, contains('ingressClassName: public'));
      expect(await clusterIssuer.check(context), isA<Satisfied>());
    });
  });
}
