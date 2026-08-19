import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The shrinking half of preserve_list: one member out, everything else back verbatim, and the two
/// refusals that keep it from taking working callers down with the removed one.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String roleKey = '$url/v1/auth/kubernetes-m1/role/secret-readers';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const RemoveVaultRoleMember step = RemoveVaultRoleMember(
    repository: repository,
    mount: '<kubernetes-mount>',
    role: 'secret-readers',
    list: 'bound_account_spaces',
    member: '<sibling>',
    layout: layout,
  );

  FakeFiles checkout() => FakeFiles(<String, String>{
    '$repository/cluster/profile.yaml':
        'global:\n'
        '  vaultUrl: $url\n'
        '  clusterName: m1\n'
        '  vaultKubernetesAuthPath: kubernetes-m1\n',
    '$repository/secrets/vault-dev.txt': renderCredentials(
      url: url,
      unsealKeys: <String>['k1'],
      rootToken: token,
    ),
  });

  StepContext contextOn(Http http) => StepContext(
    shell: FakeShell(),
    files: checkout(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('remove_vault_role_member'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    facts: Facts.none,
  );

  test('a role that is not there binds nobody — already removed', () async {
    final FakeHttp http = FakeHttp()..answers('GET $roleKey', status: 404);
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('a list not carrying the member is already removed', () async {
    final FakeHttp http = FakeHttp()
      ..answers('GET $roleKey', body: '{"data":{"bound_account_spaces":["a","b"]}}');
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('the shrink takes the one member out and carries every other field forward', () async {
    final _CapturingHttp http = _CapturingHttp(<String, HttpAnswer>{
      'GET $roleKey': _json(
        '{"data":{"bound_account_spaces":["a","s1"],"token_policies":["m1-eso"],"ttl":86400}}',
      ),
    });
    final StepContext context = contextOn(http);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    expect(http.bodies['POST $roleKey'], contains('"bound_account_spaces":["a"]'));
    expect(http.bodies['POST $roleKey'], contains('"token_policies":["m1-eso"]'));
    expect(http.bodies['POST $roleKey'], contains('"ttl":86400'));
  });

  test('the LAST member is refused — an empty binding list refuses every caller', () async {
    // The planted defect this guards: a removal that empties the list takes the working callers
    // down with the removed one, and every one of them is refused about its own token.
    final FakeHttp http = FakeHttp()
      ..answers('GET $roleKey', body: '{"data":{"bound_account_spaces":["s1"]}}');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('ONLY member'));
  });

  test('a role nobody can read never passes for one that binds nobody', () async {
    final FakeHttp http = FakeHttp()..answers('GET $roleKey', status: 500, body: 'boom');
    final CheckResult answer = await step.check(contextOn(http));
    expect(answer, isA<Blocked>());
  });

  test('the capture is the whole role, and the undo writes it back verbatim', () async {
    final _CapturingHttp http = _CapturingHttp(<String, HttpAnswer>{
      'GET $roleKey': _json('{"data":{"bound_account_spaces":["a","s1"],"ttl":86400}}'),
    });
    final StepContext context = contextOn(http);

    final Map<String, Object?>? captured = await step.capture(context);
    expect(captured?['bound_account_spaces'], <Object?>['a', 's1']);

    await step.undo(context, captured);
    expect(http.bodies['POST $roleKey'], contains('"bound_account_spaces":["a","s1"]'));
  });
}

HttpAnswer _json(String body) =>
    HttpAnswer(status: 200, body: body, headers: const <String, String>{}, elapsed: Duration.zero);

/// A fake network that also keeps the LAST body sent per `METHOD url`, so a test can hold the
/// written role against what the store answered.
final class _CapturingHttp implements Http {
  _CapturingHttp(this._answers);

  final Map<String, HttpAnswer> _answers;

  /// The last body sent per `METHOD url`.
  final Map<String, String> bodies = <String, String>{};

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final String key = '${request.method} ${request.url}';
    if (request.body case final String body) {
      bodies[key] = body;
    }
    return _answers[key] ??
        const HttpAnswer(
          status: 200,
          body: '',
          headers: <String, String>{},
          elapsed: Duration.zero,
        );
  }
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
