import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// Removing one key-value entry whole: the METADATA surface and never the soft delete, absence
/// proven and never assumed.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String metadataKey = '$url/v1/secret/metadata/dev/members/s1/keys';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const RemoveVaultKvEntry step = RemoveVaultKvEntry(
    repository: repository,
    mount: 'secret',
    path: '<stage>/members/<sibling>/keys',
    layout: layout,
  );

  FakeFiles checkout() => FakeFiles(<String, String>{
    '$repository/cluster/profile.yaml': 'global:\n  vaultUrl: $url\n  clusterName: m1\n',
    '$repository/secrets/vault-dev.txt': renderCredentials(
      url: url,
      unsealKeys: <String>['k1'],
      rootToken: token,
    ),
  });

  StepContext contextOn(FakeHttp http) => StepContext(
    shell: FakeShell(),
    files: checkout(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('remove_vault_kv_entry'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    facts: Facts.none,
  );

  test('an entry the store does not hold is already removed', () async {
    final FakeHttp http = FakeHttp()..answers('GET $metadataKey', status: 404);
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('an entry that is there goes through the METADATA delete — every version at once', () async {
    // The soft delete is the planted trap: it leaves every version standing, so a later
    // create-only write finds the slot occupied and refuses — the entry has to go whole.
    final FakeHttp http = FakeHttp()
      ..answers('GET $metadataKey', body: '{"data":{"current_version":3}}');
    final StepContext context = contextOn(http);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(http.sent, contains('DELETE $metadataKey'));
    expect(http.sent.where((String r) => r.contains('/data/')), isEmpty);
  });

  test('an answer nobody can read never passes for absence', () async {
    final FakeHttp http = FakeHttp()..answers('GET $metadataKey', status: 500, body: 'boom');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('says neither what it holds'));
  });
}

final class _NothingSaid implements Logger {
  const _NothingSaid();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
