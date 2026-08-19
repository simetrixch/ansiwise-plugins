import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// Removing one policy: absence is proven, an unreadable answer never passes for it, and the
/// capture is what an unwind writes back.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String policyKey = '$url/v1/sys/policies/acl/s1-readers';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const RemoveVaultPolicy step = RemoveVaultPolicy(
    repository: repository,
    name: '<sibling>-readers',
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
    step: const StepName('remove_vault_policy'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    facts: Facts.none,
  );

  test('a policy the store does not hold is already removed', () async {
    final FakeHttp http = FakeHttp()..answers('GET $policyKey', status: 404);
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('a policy that is there is work, and the apply deletes exactly it', () async {
    final FakeHttp http = FakeHttp()
      ..answers('GET $policyKey', body: '{"data":{"policy":"path \\"a\\" {}"}}');
    final StepContext context = contextOn(http);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(http.sent, contains('DELETE $policyKey'));
  });

  test('an answer nobody can read never passes for absence', () async {
    // The planted defect this guards: a 500 while listing read as "not there", after which the
    // removal reports done about a policy that still grants.
    final FakeHttp http = FakeHttp()..answers('GET $policyKey', status: 500, body: 'boom');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('says neither what it holds'));
  });

  test('the capture is the text as it stood, and the undo writes it back verbatim', () async {
    final FakeHttp http = FakeHttp()
      ..answers('GET $policyKey', body: '{"data":{"policy":"path \\"a\\" {}"}}');
    final StepContext context = contextOn(http);

    final String? captured = await step.capture(context);
    expect(captured, 'path "a" {}');

    await step.undo(context, captured);
    expect(http.sent, contains('PUT $policyKey'));
  });

  test('a capture that could not read THROWS rather than remembering absence', () async {
    final FakeHttp http = FakeHttp()..answers('GET $policyKey', status: 500, body: 'boom');
    await expectLater(step.capture(contextOn(http)), throwsA(isA<StateError>()));
  });

  test('an undo over captured absence leaves absence alone', () async {
    final FakeHttp http = FakeHttp();
    await step.undo(contextOn(http), null);
    expect(http.sent, isEmpty);
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
