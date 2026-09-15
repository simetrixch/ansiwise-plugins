import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

import 'dkim_fixture.dart';
import 'support/store.dart';

/// The read-only half: what the store holds under the public field is published, and an entry that
/// holds none is a refusal naming where the pair comes from.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentialsPath = '$repository/secrets/vault-dev.txt';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String publicField = 'dkim-public-key';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  const MeasureDkimPublicKey step = MeasureDkimPublicKey(
    repository: repository,
    mount: 'secret',
    path: '<stage>/app/relay',
    publicKeyField: publicField,
    layout: layout,
  );

  const String profile =
      'global:\n'
      '  vaultUrl: $url\n'
      '  clusterName: m1\n'
      '  vaultKubernetesAuthPath: kubernetes-m1\n';

  final String credentialFile = renderCredentials(
    url: url,
    unsealKeys: const <String>['k1', 'k2', 'k3'],
    rootToken: token,
  );

  ({StepContext context, Map<MeasurementName, String> published}) contextOver(FakeStore store) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{profilePath: profile, credentialsPath: credentialFile}),
        http: store,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const SilentLog(),
        step: const StepName('measure_dkim_public_key'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'stage': 'dev'}),
        facts: Facts.none,
        measurements: RecordingSink(published),
      ),
      published: published,
    );
  }

  test('an entry holding the public half publishes it, exactly as it stands', () async {
    final FakeStore store = FakeStore(
      holding: <String, Object?>{'dkim-private-key': pkcs8Fixture, publicField: publicKeyFixture},
    );
    final ({StepContext context, Map<MeasurementName, String> published}) it = contextOver(store);

    expect(await step.check(it.context), isA<Satisfied>());
    expect(it.published[const MeasurementName('dkim_public_key')], publicKeyFixture);
    expect(store.wrote, isEmpty);
  });

  test('an entry that is not there is a refusal naming where the pair comes from', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = contextOver(
      FakeStore(),
    );

    final CheckResult answer = await step.check(it.context);
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('secret/data/dev/app/relay'));
    expect(answer.reason, contains('minted where this store is seeded'));
    expect(it.published, isEmpty);
  });

  test('an entry without the public field is the same refusal', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = contextOver(
      FakeStore(holding: <String, Object?>{'dkim-private-key': pkcs8Fixture}),
    );

    expect(await step.check(it.context), isA<Blocked>());
    expect(it.published, isEmpty);
  });

  test('a read that FAILED is not an entry that holds nothing', () async {
    final CheckResult answer = await step.check(contextOver(FakeStore(readStatus: 403)).context);
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('403'));
  });
}
