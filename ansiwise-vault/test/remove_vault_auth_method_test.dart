import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// Disabling one auth mount: absence is proven, a listing nobody can read never passes for it, and
/// a mount of another type at the same path is refused rather than taken away.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String listKey = 'GET $url/v1/sys/auth';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const RemoveVaultAuthMethod step = RemoveVaultAuthMethod(
    repository: repository,
    path: 'kubernetes-<sibling>',
    type: 'kubernetes',
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
    step: const StepName('remove_vault_auth_method'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    facts: Facts.none,
  );

  test('a path holding no mount is already removed', () async {
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"token/":{"type":"token"}}}');
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('the mount an earlier run made is work, and the apply disables exactly it', () async {
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}');
    final StepContext context = contextOn(http);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(http.sent, contains('DELETE $url/v1/sys/auth/kubernetes-s1'));
  });

  test('a mount of ANOTHER type at the same path is refused, never disabled', () async {
    // The planted defect this guards: a name collision taking away something this program never
    // created — the disable would destroy that mount's accessor and every alias behind it.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"oidc"}}}');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('name collision'));
  });

  test('a listing nobody can read never passes for absence', () async {
    final FakeHttp http = FakeHttp()..answers(listKey, status: 500, body: 'boom');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('says neither'));
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
