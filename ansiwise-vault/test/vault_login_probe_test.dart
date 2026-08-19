import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The login probe: a real login attempt whose EXPECTED answer is a refusal by the role's bounds,
/// because only a validated token can be refused that way. The defect each denial guards is written
/// beside it.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String jwt = 'ThisIsNotARealReviewingCredentialItIsATestFixture';
  const String loginKey = 'POST $url/v1/auth/kubernetes-s1/login';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const VaultLoginProbe step = VaultLoginProbe(
    repository: repository,
    mount: 'kubernetes-<sibling>',
    role: 'secret-readers',
    jwtAnswer: 'reviewer_jwt',
    layout: layout,
  );

  FakeFiles checkout() => FakeFiles(<String, String>{
    '$repository/cluster/profile.yaml': 'global:\n  vaultUrl: $url\n  clusterName: m1\n',
  });

  StepContext contextOn(FakeHttp http, {Map<String, Object>? answers}) => StepContext(
    shell: FakeShell(),
    files: checkout(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('vault_login_probe'),
    arguments: Arguments.none,
    answers: Arguments(
      answers ?? const <String, Object>{'stage': 'dev', 'sibling': 's1', 'reviewer_jwt': jwt},
    ),
    facts: Facts.none,
  );

  test('a login refused by the role\'s bounds alone IS the proof — satisfied', () async {
    final FakeHttp http = FakeHttp()
      ..answers(loginKey, status: 403, body: '{"errors":["service account name not authorized"]}');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains('refused by the role\'s bounds alone'));
  });

  test('the one failure with its own repair: the review reached the cluster and could not READ '
      'there', () async {
    // Ordering is the planted trap: this message ALSO contains "not authorized", and a probe that
    // matched that first would report the wiring healthy over a cluster where every real login
    // dies on the missing read grant.
    final FakeHttp http = FakeHttp()
      ..answers(
        loginKey,
        status: 403,
        body: '{"errors":["namespace not authorized: failed to get namespace \\"x\\""]}',
      );
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('could not READ there'));
  });

  test('a wiring failure blocks, naming the three values to look at', () async {
    final FakeHttp http = FakeHttp()
      ..answers(
        loginKey,
        status: 500,
        body: '{"errors":["Post https://198.51.100.7:16443/...: dial tcp: i/o timeout"]}',
      );
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('address, certificate authority and reviewing'));
  });

  test('a login that unexpectedly went through still proves the round trip — satisfied, with the '
      'role named for checking', () async {
    final FakeHttp http = FakeHttp()..answers(loginKey, body: '{"auth":{"client_token":"t"}}');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Satisfied>());
    expect((answer as Satisfied).because, contains('check what the role "secret-readers" binds'));
  });

  test(
    'a run not holding the credential is blocked by the answer\'s name, and nothing is sent',
    () async {
      final FakeHttp http = FakeHttp();
      final CheckResult answer = await step.check(
        contextOn(http, answers: const <String, Object>{'stage': 'dev', 'sibling': 's1'}),
      );
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('reviewer_jwt'));
      expect(http.sent, isEmpty);
    },
  );

  test('the credential rides the request body and reaches no record surface', () async {
    // What a run records of a request is method, address and status — FakeHttp keeps the same —
    // so the one place the value may stand is the body, which is never kept.
    final FakeHttp http = FakeHttp()
      ..answers(loginKey, status: 403, body: '{"errors":["not authorized"]}');
    await step.check(contextOn(http));
    expect(http.sent.single, loginKey);
    expect(http.sent.single.contains(jwt), isFalse);
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
