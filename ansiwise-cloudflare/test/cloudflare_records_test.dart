import 'dart:convert';

import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';
import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:test/test.dart';

/// The record steps against a fake zone, and above all the one trap that decides whether this
/// package is safe to point at a live domain: a second `v=spf1` is REFUSED, never repaired, and a
/// single existing one is MERGED with everything already in it preserved.
///
/// Every case here is a mistake that costs real mail. The apex of a live domain is routinely
/// somebody else's operating mail domain — the existing SPF is their production — so the innocent
/// case (one record, foreign mechanisms kept) and the planted defect (two records, wholesale
/// refusal naming both) are both pinned against the exact bytes that would be written.
void main() {
  const String api = 'https://api.example.test/v4';
  const String repository = '/srv/checkout';
  const String secretsFile = '$repository/secrets/values.dev';
  const String apex = 'example.com';
  const String address = '203.0.113.25';

  const CloudflareAccess access = CloudflareAccess(
    apiUrl: api,
    repository: repository,
    secrets: 'secrets/values.<stage>',
    tokenVariable: 'DNS_API_TOKEN',
    runAnswer: 'stage',
  );

  const Arguments answers = Arguments(<String, Object>{
    'stage': 'dev',
    'mail_domain': apex,
    'egress_address': address,
    'dkim_selector': 'key1',
    'dmarc_policy': 'none',
    'dmarc_mailbox': 'reports@example.com',
  });

  FakeFiles filledInput([String extra = '']) =>
      FakeFiles(<String, String>{secretsFile: 'DNS_API_TOKEN=cf-token-fixture-not-real\n$extra'});

  StepContext contextOf({required FakeFiles files, required Http http}) => StepContext(
    shell: FakeShell(),
    files: files,
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _QuietLog(),
    step: const StepName('probe'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  const CloudflareSpfRecord spfStep = CloudflareSpfRecord(
    access: access,
    apexAnswer: 'mail_domain',
    addressAnswer: 'egress_address',
    allMechanism: '-all',
  );

  /// A zone whose apex TXT slot holds [txt], behind the usual token and zone lookups.
  _Zone zoneWithApexTxt(List<Map<String, Object?>> txt) => _Zone(<String, String>{
    'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
      <String, Object?>{'id': 'zone-1', 'name': apex},
    ]),
    'GET $api/zones/zone-1/dns_records?type=TXT&name=$apex&per_page=100': _ok(txt),
  });

  group('the SPF trap', () {
    test('TWO v=spf1 records refuse the domain wholesale, naming both', () async {
      final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
        _txt('rec-1', apex, 'v=spf1 include:spf.partner.example -all'),
        _txt('rec-2', apex, 'v=spf1 ip4:198.51.100.7 ~all'),
        _txt('rec-3', apex, 'some-site-verification=abc123'),
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Blocked>());
      final String reason = (result as Blocked).reason;
      expect(reason, contains('2 v=spf1 records'));
      expect(reason, contains('v=spf1 include:spf.partner.example -all'));
      expect(reason, contains('v=spf1 ip4:198.51.100.7 ~all'));

      await expectLater(spfStep.apply(context), throwsStateError);
      expect(
        zone.sent.where((HttpRequest r) => r.method != 'GET'),
        isEmpty,
        reason:
            'a domain with two SPF records is already broken, and the one thing this step '
            'guarantees is that it never writes a third opinion into it',
      );
    });

    test(
      'ONE existing record is merged, keeping the foreign mechanisms and the qualifier',
      () async {
        final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
          _txt('rec-1', apex, 'v=spf1 include:spf.partner.example ~all'),
        ]);
        final StepContext context = contextOf(files: filledInput(), http: zone);

        expect(await spfStep.check(context), isA<Ready>());
        await spfStep.apply(context);

        final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
        expect(write.method, 'PUT');
        expect(write.url, '$api/zones/zone-1/dns_records/rec-1');
        final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
        expect(
          body['content'],
          'v=spf1 include:spf.partner.example ip4:$address ~all',
          reason:
              'the other service\'s include is somebody\'s production mail and the ~all is the '
              'domain owner\'s policy — the merge may add one mechanism and change nothing else',
        );
      },
    );

    test('a record that already authorises the address is left untouched', () async {
      final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
        _txt('rec-1', apex, 'v=spf1 include:spf.partner.example ip4:$address ~all'),
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Satisfied>());
      expect((result as Satisfied).because, contains('include:spf.partner.example'));
      expect(zone.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
    });

    test('no SPF at all creates a fresh record closed by the row\'s all-mechanism', () async {
      final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
        _txt('rec-3', apex, 'some-site-verification=abc123'),
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      expect(await spfStep.check(context), isA<Ready>());
      await spfStep.apply(context);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      expect(write.method, 'POST');
      expect(write.url, '$api/zones/zone-1/dns_records');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body['content'], 'v=spf1 ip4:$address -all');
      expect(body['name'], apex);
      expect(body['type'], 'TXT');
    });

    test('a listing that cannot be read blocks rather than passing for an empty zone', () async {
      final _Zone zone = _Zone(<String, String>{
        'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
          <String, Object?>{'id': 'zone-1', 'name': apex},
        ]),
        'GET $api/zones/zone-1/dns_records?type=TXT&name=$apex&per_page=100': _refusal(status: 500),
      });
      final StepContext context = contextOf(files: filledInput(), http: zone);

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Blocked>());
      expect(
        (result as Blocked).reason,
        contains('500'),
        reason:
            'a failure read as "nothing is there" is what makes a tool write a fresh SPF over a '
            'live one',
      );
      await expectLater(spfStep.apply(context), throwsStateError);
      expect(zone.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
    });
  });

  group('the address record', () {
    const CloudflareARecord step = CloudflareARecord(
      access: access,
      fqdnAnswer: 'mail_domain',
      addressAnswer: 'egress_address',
      proxied: false,
    );

    _Zone zoneWithA(List<Map<String, Object?>> records) => _Zone(<String, String>{
      'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
        <String, Object?>{'id': 'zone-1', 'name': apex},
      ]),
      'GET $api/zones/zone-1/dns_records?type=A&name=$apex&per_page=100': _ok(records),
    });

    test('an absent record is created with the full desired body', () async {
      final _Zone zone = zoneWithA(<Map<String, Object?>>[]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      expect(write.method, 'POST');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body, <String, Object?>{
        'type': 'A',
        'name': apex,
        'content': address,
        'ttl': 1,
        'proxied': false,
      });
    });

    test(
      'a record with the right address but proxied on is drift, and the apply greys it',
      () async {
        // The one field difference that silently breaks outbound mail: the answer becomes the
        // service's own addresses, which carry no mail path.
        final _Zone zone = zoneWithA(<Map<String, Object?>>[
          <String, Object?>{
            'id': 'rec-a',
            'type': 'A',
            'name': apex,
            'content': address,
            'proxied': true,
          },
        ]);
        final StepContext context = contextOf(files: filledInput(), http: zone);

        expect(await step.check(context), isA<Ready>());
        await step.apply(context);

        final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
        expect(write.method, 'PUT');
        expect(write.url, '$api/zones/zone-1/dns_records/rec-a');
        final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
        expect(body['proxied'], false);
      },
    );

    test('a record already right, proxied off included, satisfies without a write', () async {
      final _Zone zone = zoneWithA(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'rec-a',
          'type': 'A',
          'name': apex,
          'content': address,
          'proxied': false,
        },
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      expect(await step.check(context), isA<Satisfied>());
      expect(zone.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
    });

    test('two address records at the name refuse, naming what stands there', () async {
      final _Zone zone = zoneWithA(<Map<String, Object?>>[
        <String, Object?>{
          'id': 'rec-a',
          'type': 'A',
          'name': apex,
          'content': address,
          'proxied': false,
        },
        <String, Object?>{
          'id': 'rec-b',
          'type': 'A',
          'name': apex,
          'content': '198.51.100.7',
          'proxied': false,
        },
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      final CheckResult result = await step.check(context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('198.51.100.7'));
    });

    test('the zone is found by walking the labels of a deeper name', () async {
      const CloudflareARecord deep = CloudflareARecord(
        access: access,
        fqdnAnswer: 'machine_name',
        addressAnswer: 'egress_address',
        proxied: false,
      );
      final _Zone zone = _Zone(<String, String>{
        'GET $api/zones?name=m1.$apex&per_page=1': _ok(<Object?>[]),
        'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
          <String, Object?>{'id': 'zone-1', 'name': apex},
        ]),
        'GET $api/zones/zone-1/dns_records?type=A&name=m1.$apex&per_page=100': _ok(<Object?>[]),
      });
      final StepContext context = StepContext(
        shell: FakeShell(),
        files: filledInput(),
        http: zone,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const _QuietLog(),
        step: const StepName('probe'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{
          'stage': 'dev',
          'machine_name': 'm1.$apex',
          'egress_address': address,
        }),
        facts: Facts.none,
      );

      expect(await deep.check(context), isA<Ready>());
    });
  });

  group('the token', () {
    test('a missing hand-filled input blocks by path, and nothing is sent anywhere', () async {
      final _Zone zone = _Zone(const <String, String>{});
      final StepContext context = contextOf(files: FakeFiles(), http: zone);

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(secretsFile));
      expect(zone.sent, isEmpty, reason: 'a step without a token must not reach for the zone');
    });

    test('an empty token variable blocks by variable name, never printing a value', () async {
      final _Zone zone = _Zone(const <String, String>{});
      final StepContext context = contextOf(
        files: FakeFiles(<String, String>{secretsFile: 'DNS_API_TOKEN=\n'}),
        http: zone,
      );

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('DNS_API_TOKEN'));
      expect(zone.sent, isEmpty);
    });

    test('a carriage return in the input is refused before any value is read', () async {
      final _Zone zone = _Zone(const <String, String>{});
      final StepContext context = contextOf(
        files: FakeFiles(<String, String>{secretsFile: 'DNS_API_TOKEN=abc\r\n'}),
        http: zone,
      );

      final CheckResult result = await spfStep.check(context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('carriage return'));
      expect(zone.sent, isEmpty);
    });
  });

  group('the DKIM record', () {
    const CloudflareDkimRecord step = CloudflareDkimRecord(
      access: access,
      apexAnswer: 'mail_domain',
      selectorAnswer: 'dkim_selector',
      publicKeyVariable: 'MAIL_SIGNING_PUBLIC_KEY',
    );
    const String dkimName = 'key1._domainkey.$apex';
    const String key = 'MIIBIjANBgkqAAAA';

    test('an empty key variable publishes NOTHING and says so out loud', () async {
      final _Zone zone = _Zone(const <String, String>{});
      final StepContext context = contextOf(
        files: filledInput('MAIL_SIGNING_PUBLIC_KEY=\n'),
        http: zone,
      );

      final CheckResult result = await step.check(context);

      expect(result, isA<Satisfied>());
      expect((result as Satisfied).because, contains('MAIL_SIGNING_PUBLIC_KEY'));
      expect(result.because, contains('no signing key'));
      expect(
        zone.sent,
        isEmpty,
        reason:
            'a DKIM record nothing signs with makes receivers fail mail that is otherwise fine, '
            'so with no key the zone is not even asked',
      );
    });

    test('a filled key composes the name and the record text DKIM prescribes', () async {
      final _Zone zone = _Zone(<String, String>{
        'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
          <String, Object?>{'id': 'zone-1', 'name': apex},
        ]),
        'GET $api/zones/zone-1/dns_records?type=TXT&name=$dkimName&per_page=100': _ok(<Object?>[]),
      });
      final StepContext context = contextOf(
        files: filledInput('MAIL_SIGNING_PUBLIC_KEY=$key\n'),
        http: zone,
      );

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body['name'], dkimName);
      expect(body['content'], 'v=DKIM1; h=sha256; k=rsa; p=$key');
    });

    test('a stored key the zone chunked reads back as the same record', () async {
      // The API stores a long TXT as quoted 255-character pieces. Compared raw, a correct record
      // is drift on every run and is rewritten forever.
      final _Zone zone = _Zone(<String, String>{
        'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
          <String, Object?>{'id': 'zone-1', 'name': apex},
        ]),
        'GET $api/zones/zone-1/dns_records?type=TXT&name=$dkimName&per_page=100': _ok(<Object?>[
          _txt('rec-k', dkimName, '"v=DKIM1; h=sha256; k=rsa; " "p=$key"'),
        ]),
      });
      final StepContext context = contextOf(
        files: filledInput('MAIL_SIGNING_PUBLIC_KEY=$key\n'),
        http: zone,
      );

      expect(await step.check(context), isA<Satisfied>());
      expect(zone.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
    });
  });

  group('the DMARC record', () {
    const CloudflareDmarcRecord step = CloudflareDmarcRecord(
      access: access,
      apexAnswer: 'mail_domain',
      policyAnswer: 'dmarc_policy',
      mailboxAnswer: 'dmarc_mailbox',
    );
    const String dmarcName = '_dmarc.$apex';

    test('composes the record text DMARC prescribes and creates it', () async {
      final _Zone zone = _Zone(<String, String>{
        'GET $api/zones?name=$apex&per_page=1': _ok(<Object?>[
          <String, Object?>{'id': 'zone-1', 'name': apex},
        ]),
        'GET $api/zones/zone-1/dns_records?type=TXT&name=$dmarcName&per_page=100': _ok(<Object?>[]),
      });
      final StepContext context = contextOf(files: filledInput(), http: zone);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body['name'], dmarcName);
      expect(body['content'], 'v=DMARC1; p=none; rua=mailto:reports@example.com');
    });

    test('a policy word DMARC does not define is refused with the legal three', () async {
      final _Zone zone = _Zone(const <String, String>{});
      final StepContext context = StepContext(
        shell: FakeShell(),
        files: filledInput(),
        http: zone,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const _QuietLog(),
        step: const StepName('probe'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{
          'stage': 'dev',
          'mail_domain': apex,
          'dmarc_policy': 'block',
          'dmarc_mailbox': 'reports@example.com',
        }),
        facts: Facts.none,
      );

      final CheckResult result = await step.check(context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('none, quarantine, reject'));
      expect(zone.sent, isEmpty);
    });
  });

  group('taking the work back', () {
    test('capture keeps the record about to be overwritten, and undo writes it back', () async {
      final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
        _txt('rec-1', apex, 'v=spf1 include:spf.partner.example ~all'),
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);

      final CapturedRecord captured = await spfStep.capture(context);
      expect(captured.wasThere, isTrue);
      expect(captured.content, 'v=spf1 include:spf.partner.example ~all');

      await spfStep.undo(context, captured);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      expect(write.method, 'PUT');
      expect(write.url, '$api/zones/zone-1/dns_records/rec-1');
      final Map<String, Object?> body = jsonDecode(write.body!) as Map<String, Object?>;
      expect(body['content'], 'v=spf1 include:spf.partner.example ~all');
    });

    test('a slot captured empty has the step\'s own record removed on undo', () async {
      // The zone as the undo finds it: the apply created one SPF record; the capture from before
      // says nothing stood there.
      final _Zone zone = zoneWithApexTxt(<Map<String, Object?>>[
        _txt('rec-9', apex, 'v=spf1 ip4:$address -all'),
        _txt('rec-3', apex, 'some-site-verification=abc123'),
      ]);
      final StepContext context = contextOf(files: filledInput(), http: zone);
      const CapturedRecord captured = CapturedRecord.absent(
        zoneId: 'zone-1',
        type: 'TXT',
        name: apex,
      );

      await spfStep.undo(context, captured);

      final HttpRequest write = zone.sent.singleWhere((HttpRequest r) => r.method != 'GET');
      expect(write.method, 'DELETE');
      expect(
        write.url,
        '$api/zones/zone-1/dns_records/rec-9',
        reason:
            'only the SPF record the step maintains is removed — the verification record beside '
            'it belongs to somebody else and survives the undo',
      );
    });
  });
}

/// One TXT record as a zone listing carries it.
Map<String, Object?> _txt(String id, String name, String content) => <String, Object?>{
  'id': id,
  'type': 'TXT',
  'name': name,
  'content': content,
};

/// A successful v4 answer carrying [result].
String _ok(Object? result) =>
    jsonEncode(<String, Object?>{'success': true, 'errors': <Object?>[], 'result': result});

/// A refused v4 answer, as the API words one.
String _refusal({required int status}) => jsonEncode(<String, Object?>{
  'success': false,
  'errors': <Object?>[
    <String, Object?>{'code': status * 10, 'message': 'the zone said no'},
  ],
  'result': null,
});

/// A network port that answers a table of `METHOD url` keys and keeps every request, body included.
///
/// [FakeHttp] keeps only `METHOD url`, and half of what these tests pin is the exact BYTES a write
/// would put into a live zone — so the requests themselves are kept. A key with no entry answers a
/// successful empty write, which is what the API answers a correct mutation with.
final class _Zone implements Http {
  _Zone(this._answers);

  final Map<String, String> _answers;

  /// Every request that was sent, in order.
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    sent.add(request);
    final String? body = _answers['${request.method} ${request.url}'];
    return HttpAnswer(
      status: body == null ? 200 : (body.contains('"success":false') ? 500 : 200),
      body: body ?? _ok(<String, Object?>{'id': 'written'}),
      headers: const <String, String>{},
      elapsed: Duration.zero,
    );
  }
}

/// A logger that keeps quiet, so a step's own notes do not land inside the test output.
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
