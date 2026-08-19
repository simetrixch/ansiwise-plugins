import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The auth-method configuration a program file cannot hold: the keys written from answers, the
/// one that travels base64 because it has line breaks, and the one Vault never returns — with the
/// convergence trap each of the three exists for planted beside it.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String pem = '-----BEGIN CERTIFICATE-----\nMIIB\n-----END CERTIFICATE-----\n';
  const String jwt = 'ThisIsNotARealReviewingCredentialItIsATestFixture';
  const String listKey = 'GET $url/v1/sys/auth';
  const String configKey = '$url/v1/auth/kubernetes-s1/config';
  final String caEncoded = base64Encode(utf8.encode(pem));

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
    type: 'kubernetes',
    path: 'kubernetes-<sibling>',
    layout: layout,
    configuration: '{"use_annotations_as_alias_metadata":true}',
    configurationFromAnswers: <String>[
      'kubernetes_host=api_server_url',
      'kubernetes_ca_cert=ca_data',
      'token_reviewer_jwt=reviewer_jwt',
    ],
    configurationDecoded: <String>['kubernetes_ca_cert'],
    configurationWriteOnly: <String>['token_reviewer_jwt'],
  );

  FakeFiles checkout() => FakeFiles(<String, String>{
    '$repository/cluster/profile.yaml': 'global:\n  vaultUrl: $url\n  clusterName: m1\n',
    '$repository/secrets/vault-dev.txt': renderCredentials(
      url: url,
      unsealKeys: <String>['k1'],
      rootToken: token,
    ),
  });

  StepContext contextOn(Http http, {Map<String, Object>? answers}) => StepContext(
    shell: FakeShell(),
    files: checkout(),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('vault_auth_method'),
    arguments: Arguments.none,
    answers: Arguments(
      answers ??
          <String, Object>{
            'stage': 'dev',
            'sibling': 's1',
            'api_server_url': 'https://198.51.100.7:16443',
            'ca_data': caEncoded,
            'reviewer_jwt': jwt,
          },
    ),
    facts: Facts.none,
  );

  test('the apply writes the file\'s keys and the answers\' keys as ONE object, the encoded one '
      'decoded', () async {
    final _CapturingHttp http = _CapturingHttp(<String, HttpAnswer>{
      listKey: _json('{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}'),
    });
    await step.apply(contextOn(http));

    final Map<String, Object?> written =
        jsonDecode(http.bodies['POST $configKey']!) as Map<String, Object?>;
    expect(written['use_annotations_as_alias_metadata'], true);
    expect(written['kubernetes_host'], 'https://198.51.100.7:16443');
    expect(written['kubernetes_ca_cert'], pem);
    expect(written['token_reviewer_jwt'], jwt);
  });

  test('a mount already holding every comparable key is satisfied — the write-only one is not '
      'compared', () async {
    // The convergence trap: Vault never returns token_reviewer_jwt, so a check comparing it finds
    // it missing on every run, rewrites, asks again — and the step can never call itself finished.
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}')
      ..answers(
        'GET $configKey',
        body:
            '{"data":{"use_annotations_as_alias_metadata":true,'
            '"kubernetes_host":"https://198.51.100.7:16443",'
            '"kubernetes_ca_cert":${jsonEncode(pem)}}}',
      );
    expect(await step.check(contextOn(http)), isA<Satisfied>());
  });

  test('a mount whose comparable key differs is work to do', () async {
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}')
      ..answers(
        'GET $configKey',
        body:
            '{"data":{"use_annotations_as_alias_metadata":true,'
            '"kubernetes_host":"https://203.0.113.9:16443",'
            '"kubernetes_ca_cert":${jsonEncode(pem)}}}',
      );
    expect(await step.check(contextOn(http)), isA<Ready>());
  });

  test('a run not holding a named answer is blocked by that answer\'s name', () async {
    final FakeHttp http = FakeHttp()
      ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}');
    final CheckResult answer = await step.check(
      contextOn(
        http,
        answers: <String, Object>{
          'stage': 'dev',
          'sibling': 's1',
          'api_server_url': 'https://198.51.100.7:16443',
          'ca_data': caEncoded,
        },
      ),
    );
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('reviewer_jwt'));
  });

  test(
    'an answer that does not decode as base64 is refused where the row declared decoding',
    () async {
      final FakeHttp http = FakeHttp()
        ..answers(listKey, body: '{"data":{"kubernetes-s1/":{"type":"kubernetes"}}}');
      final CheckResult answer = await step.check(
        contextOn(
          http,
          answers: <String, Object>{
            'stage': 'dev',
            'sibling': 's1',
            'api_server_url': 'https://198.51.100.7:16443',
            'ca_data': 'not base64 at all!',
            'reviewer_jwt': jwt,
          },
        ),
      );
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('does not decode as base64'));
    },
  );
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
