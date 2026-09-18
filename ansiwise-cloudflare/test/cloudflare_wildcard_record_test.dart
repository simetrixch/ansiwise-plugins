import 'dart:convert';

import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

// The wildcard of an installation: one CNAME at `*.<fqdn>` answering `<fqdn>`, kept the way the
// address record is kept — read first, created where absent, replaced whole where it drifts, refused
// where several stand, and given back on undo (#187).
void main() {
  const String api = 'https://api.example.test/v4';
  const String repository = '/srv/checkout';
  const String secretsFile = '$repository/secrets/values.dev';
  const String fqdn = 'apps7.example.com';
  const String zoneName = 'example.com';
  const String wildcard = '*.$fqdn';

  const CloudflareAccess access = CloudflareAccess(
    apiUrl: api,
    repository: repository,
    secrets: 'secrets/values.<stage>',
    tokenVariable: 'DNS_API_TOKEN',
    runAnswer: 'stage',
  );
  const CloudflareWildcardRecord step = CloudflareWildcardRecord(
    access: access,
    fqdnAnswer: 'fqdn',
  );
  const Arguments answers = Arguments(<String, Object>{'stage': 'dev', 'fqdn': fqdn});

  StepContext contextOf(Http http) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(<String, String>{secretsFile: 'DNS_API_TOKEN=cf-token-fixture-not-real\n'}),
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _QuietLog(),
    step: const StepName('probe'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  // The zone is walked from the name itself: apps7.example.com is no zone, example.com is.
  _Zone zoneWith(List<Map<String, Object?>> records) => _Zone(<String, String>{
    'GET $api/zones?name=$fqdn&per_page=1': _ok(<Object?>[]),
    'GET $api/zones?name=$zoneName&per_page=1': _ok(<Object?>[
      <String, Object?>{'id': 'zone-1', 'name': zoneName},
    ]),
    'GET $api/zones/zone-1/dns_records?type=CNAME&name=$wildcard&per_page=100': _ok(records),
  });

  Map<String, Object?> cname(String id, String content, {bool proxied = false}) =>
      <String, Object?>{
        'id': id,
        'type': 'CNAME',
        'name': wildcard,
        'content': content,
        'proxied': proxied,
      };

  test('an absent wildcard is created as one CNAME to the name, proxied off', () async {
    final _Zone zone = zoneWith(<Map<String, Object?>>[]);
    final StepContext context = contextOf(zone);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
    expect(write.method, 'POST');
    expect(write.url, '$api/zones/zone-1/dns_records');
    expect(jsonDecode(write.body!), <String, Object?>{
      'type': 'CNAME',
      'name': wildcard,
      'content': fqdn,
      'ttl': 1,
      'proxied': false,
    });
    // Never asked as a zone: the walk starts at the name, not at the wildcard.
    expect(zone.sent.any((HttpRequest r) => r.url.contains('zones?name=*.')), isFalse);
  });

  test('a wildcard already answering the name, proxied off, satisfies without a write', () async {
    final _Zone zone = zoneWith(<Map<String, Object?>>[cname('rec-w', fqdn)]);
    final StepContext context = contextOf(zone);

    expect(await step.check(context), isA<Satisfied>());
    await step.apply(context);
    expect(zone.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
  });

  test('a wildcard at another target, or proxied on, is drift and is replaced whole', () async {
    for (final Map<String, Object?> held in <Map<String, Object?>>[
      cname('rec-w', 'old.example.com'),
      cname('rec-w', fqdn, proxied: true),
    ]) {
      final _Zone zone = zoneWith(<Map<String, Object?>>[held]);
      final StepContext context = contextOf(zone);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      expect(write.method, 'PUT');
      expect(write.url, '$api/zones/zone-1/dns_records/rec-w');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body['content'], fqdn);
      expect(body['proxied'], false);
    }
  });

  test('two records at the wildcard are refused by name, and nothing is written', () async {
    final _Zone zone = zoneWith(<Map<String, Object?>>[
      cname('rec-1', fqdn),
      cname('rec-2', 'other.example.com'),
    ]);
    final StepContext context = contextOf(zone);

    final CheckResult result = await step.check(context);
    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('2 alias records stand at $wildcard'));
    expect(await step.plan(context), isA<NothingPlan>());
  });

  test('capture keeps the record about to be overwritten, and undo writes it back', () async {
    final _Zone zone = zoneWith(<Map<String, Object?>>[cname('rec-w', 'old.example.com')]);
    final StepContext context = contextOf(zone);

    final CapturedRecord captured = await step.capture(context);
    expect(captured.wasThere, isTrue);
    expect(captured.content, 'old.example.com');

    await step.undo(context, captured);

    final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
    expect(write.method, 'PUT');
    expect(write.url, '$api/zones/zone-1/dns_records/rec-w');
    expect((jsonDecode(write.body!) as Map<String, Object?>)['content'], 'old.example.com');
  });
}

String _ok(Object? result) =>
    jsonEncode(<String, Object?>{'success': true, 'errors': <Object?>[], 'result': result});

final class _Zone implements Http {
  _Zone(this._answers);

  final Map<String, String> _answers;

  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    sent.add(request);
    final String? body = _answers['${request.method} ${request.url}'];
    return HttpAnswer(
      status: 200,
      body: body ?? _ok(<String, Object?>{'id': 'written'}),
      headers: const <String, String>{},
      elapsed: Duration.zero,
    );
  }
}

final class _QuietLog implements Logger {
  const _QuietLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
