import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The auth-method configuration that neither the program file nor the run holds, because this
/// Vault minted it: an identity provider's client secret, generated into the store by an earlier
/// row and readable nowhere else.
///
/// Measured on a machine: the mount stood enabled with no configuration at all, `auth/oidc/config`
/// answered `No value found`, and every browser login ended on `Invalid role` — a message about the
/// role, which existed, rather than about the configuration, which did not.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String clientSecret = 'ThisIsNotARealClientSecretItIsATestFixture';
  const String listKey = 'GET $url/v1/sys/auth';
  const String entryKey = 'GET $url/v1/secret/data/dev/idp/bootstrap';
  const String configKey = '$url/v1/auth/oidc/config';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const VaultAuthMethod step = VaultAuthMethod(
    repository: repository,
    type: 'oidc',
    path: 'oidc',
    layout: layout,
    configuration:
        '{"oidc_discovery_url":"https://idp.example.com/application/o/vault/",'
        '"oidc_client_id":"vault","default_role":"default"}',
    configurationFromEntries: <String>[
      'oidc_client_secret=secret/<stage>/idp/bootstrap:vault-client-secret',
    ],
    // Vault takes the client secret and its config read omits it, which is the same convergence
    // trap a reviewing credential has: comparing it would find it missing on every run.
    configurationWriteOnly: <String>['oidc_client_secret'],
  );

  FakeFiles checkout() => FakeFiles(<String, String>{
    '$repository/cluster/profile.yaml': 'global:\n  vaultUrl: $url\n  clusterName: m1\n',
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
    step: const StepName('vault_auth_method'),
    arguments: Arguments.none,
    answers: const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    facts: Facts.none,
  );

  test('the minted secret reaches the mount beside the keys the row states', () async {
    final _CapturingHttp http = _CapturingHttp(<String, HttpAnswer>{
      listKey: _json('{"data":{"oidc/":{"type":"oidc"}}}'),
      entryKey: _json('{"data":{"data":{"vault-client-secret":"$clientSecret"}}}'),
    });

    await step.apply(contextOn(http));

    final Map<String, Object?> written =
        jsonDecode(http.bodies['POST $configKey']!) as Map<String, Object?>;
    expect(written['oidc_discovery_url'], 'https://idp.example.com/application/o/vault/');
    expect(written['oidc_client_id'], 'vault');
    expect(written['default_role'], 'default');
    expect(
      written['oidc_client_secret'],
      clientSecret,
      reason: 'the value exists only in the store, so this is the only way it can reach the mount',
    );
  });

  test('an entry that does not carry the field is refused by that field\'s name', () async {
    // THE SHAPE THIS CATCHES. The entry is written by an earlier row, so a run arriving here
    // without the field skipped that row rather than failed it — and a step that wrote the mount
    // anyway would leave a configuration whose client secret is absent, which Vault accepts and
    // every login then fails on.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}')
      ..answers(entryKey, body: '{"data":{"data":{"another-client-secret":"$clientSecret"}}}');

    final CheckResult answer = await step.check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('vault-client-secret'));
    expect(answer.reason, contains('secret/data/dev/idp/bootstrap'));
  });

  test('a key the row writes AND an entry writes is refused, never silently ranked', () async {
    const VaultAuthMethod twice = VaultAuthMethod(
      repository: repository,
      type: 'oidc',
      path: 'oidc',
      layout: layout,
      configuration: '{"oidc_client_secret":"written-on-the-row"}',
      configurationFromEntries: <String>[
        'oidc_client_secret=secret/<stage>/idp/bootstrap:vault-client-secret',
      ],
    );
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}')
      ..answers(entryKey, body: '{"data":{"data":{"vault-client-secret":"$clientSecret"}}}');

    final CheckResult answer = await twice.check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('one key holds one value'));
  });

  test('a reference that is not a <key>=<mount>/<path>:<field> is refused as written', () async {
    const VaultAuthMethod malformed = VaultAuthMethod(
      repository: repository,
      type: 'oidc',
      path: 'oidc',
      layout: layout,
      configurationFromEntries: <String>['oidc_client_secret=<stage>/idp/bootstrap'],
    );
    final FakeHttp http = FakeHttp()..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}');

    final CheckResult answer = await malformed.check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('<key>=<mount>/<path>:<field>'));
  });

  test('a mount already holding the comparable keys is satisfied', () async {
    // THE INNOCENT CASE, and the convergence half: the client secret is write-only, so what
    // decides is the three keys Vault does return. Without this a green suite could mean the step
    // refuses every mount rather than the ones it should.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}')
      ..answers(entryKey, body: '{"data":{"data":{"vault-client-secret":"$clientSecret"}}}')
      ..answers(
        'GET $configKey',
        body:
            '{"data":{"oidc_discovery_url":"https://idp.example.com/application/o/vault/",'
            '"oidc_client_id":"vault","default_role":"default"}}',
      );

    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('a mount holding no configuration at all is work to do', () async {
    // The state the machine was found in: enabled, and told nothing.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}')
      ..answers(entryKey, body: '{"data":{"data":{"vault-client-secret":"$clientSecret"}}}')
      ..answers('GET $configKey', status: 404, body: '{"errors":[]}');

    expect(await step.check(contextOn(http)), isA<Ready>());
  });

  test('nothing is enabled when the configuration cannot be composed', () async {
    // THE STATE THIS ROW EXISTS TO PREVENT, reached by the row itself: enable first and the entry
    // read then refuses, and what is left standing is an enabled mount that was told nothing —
    // which answers every login with a message about a backend. Composed first, the refusal is
    // raised before the store has been touched at all.
    final _CapturingHttp http = _CapturingHttp(<String, HttpAnswer>{
      listKey: _json('{"data":{}}'),
      entryKey: _json('{"data":{"data":{"another-client-secret":"$clientSecret"}}}'),
    });

    await expectLater(
      step.apply(contextOn(http)),
      throwsA(
        isA<StateError>().having(
          (StateError failure) => failure.message,
          'message',
          contains('vault-client-secret'),
        ),
      ),
    );
    expect(
      http.bodies.keys,
      isNot(contains('POST $url/v1/sys/auth/oidc')),
      reason: 'a mount enabled here is a mount nothing then tells anything',
    );
  });

  test('a read that failed is not reported as a row somebody skipped', () async {
    // A refused read, a 500 and a body that will not decode all say nothing about what the entry
    // holds. Reported as "the entry does not carry the field", each of them sends an operator to an
    // earlier row that ran correctly.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"oidc/":{"type":"oidc"}}}')
      ..answers(entryKey, status: 403, body: '{"errors":["permission denied"]}');

    final CheckResult answer = await step.check(contextOn(http));

    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('403'));
    expect(
      answer.reason,
      isNot(contains('skipped that row')),
      reason: 'nothing here measured whether an earlier row ran',
    );
  });
}

HttpAnswer _json(String body) =>
    HttpAnswer(status: 200, body: body, headers: const <String, String>{}, elapsed: Duration.zero);

/// A fake network that also keeps the LAST body sent per `METHOD url`, so a test can hold the
/// written configuration against what the store was told.
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
