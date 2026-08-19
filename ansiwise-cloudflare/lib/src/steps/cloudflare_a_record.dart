import 'package:ansiwise_core/ansiwise_core.dart';

import 'cloudflare_api.dart';

/// Keeps one name answering one IPv4 address, as a single address record of its zone.
///
/// **Upsert by (name, type), never a blind creation and never a delete-all.** The slot is read
/// first: a record that is already right is left alone, one that differs is REPLACED with the full
/// desired body, and one that is missing is created. Replacing with the full body is what makes
/// this self-heal drift — a stale address, an accidentally proxied entry — instead of patching one
/// field and trusting the rest.
///
/// **Whether the record is proxied is part of the desired state, and the default is not.** For a
/// name mail is sent from, a proxied record is not a cosmetic difference: it answers with the
/// service's own addresses, which carry no mail path, and reverse-DNS alignment breaks with nothing
/// naming the cause. So the row states it, the comparison includes it, and a record found proxied
/// when the row says otherwise is drift that the next apply corrects.
///
/// **More than one address record at the name is a refusal, not a choice.** Several records there
/// mean somebody arranged something — round-robin, a migration — that this step does not
/// understand, and picking one to overwrite would dismantle it. The refusal names what stands
/// there, and a hand decides.
final class CloudflareARecord extends ReversibleStep<CapturedRecord> {
  /// Keeps the name in the answer named by [fqdnAnswer] answering the address in the answer named
  /// by [addressAnswer].
  const CloudflareARecord({
    required this.access,
    required this.fqdnAnswer,
    required this.addressAnswer,
    required this.proxied,
  });

  /// Builds the step from what the program gave it.
  factory CloudflareARecord.fromArguments(Arguments arguments) => CloudflareARecord(
    access: CloudflareAccess.fromArguments(arguments),
    fqdnAnswer: arguments.text('fqdn_answer'),
    addressAnswer: arguments.text('address_answer'),
    proxied: arguments.has('proxied') && arguments.flag('proxied'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...CloudflareAccess.arguments,
    ArgumentSpec(
      name: 'fqdn_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the full name the record answers under. Named rather '
          'than written, because a run is what knows which installation this is',
    ),
    ArgumentSpec(
      name: 'address_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the IPv4 address the name answers with — the machine '
          'the traffic should actually reach',
    ),
    ArgumentSpec(
      name: 'proxied',
      kind: ArgumentKind.flag,
      required: false,
      defaultValue: false,
      describes:
          'whether the record hides behind the service\'s own addresses. Off unless a row says '
          'otherwise, and a name mail leaves from keeps it off: a proxied answer carries no mail '
          'path and breaks reverse-DNS alignment',
    ),
  ];

  /// Where the API and the token are found.
  final CloudflareAccess access;

  /// The name of the answer holding the record's full name.
  final String fqdnAnswer;

  /// The name of the answer holding the IPv4 address.
  final String addressAnswer;

  /// Whether the desired record is proxied.
  final bool proxied;

  /// One decision for check, plan and apply, so the three cannot drift apart.
  Future<RecordDecision> _decide(StepContext context) async {
    final CloudflareToken token = await access.tokenFrom(context);
    if (token.refusal case final String refusal) {
      return RecordRefused(refusal);
    }
    final String? fqdn = answeredText(context, fqdnAnswer);
    if (fqdn == null) {
      return RecordRefused(missingAnswerRefusal(fqdnAnswer, 'the name the record answers under'));
    }
    final String? address = answeredText(context, addressAnswer);
    if (address == null) {
      return RecordRefused(
        missingAnswerRefusal(addressAnswer, 'the address the name answers with'),
      );
    }
    if (!isCidr('$address/32')) {
      return RecordRefused(
        '"$addressAnswer" holds "$address", which is not an IPv4 address — an address record '
        'made from it would be refused by the zone or, worse, accepted as something else',
      );
    }
    final ZoneLookup zone = await zoneFor(
      context,
      access: access,
      token: token.value ?? '',
      fqdn: fqdn,
    );
    if (zone case ZoneUnknown(:final String because)) {
      return RecordRefused(because);
    }
    final String zoneId = (zone as ZoneFound).id;
    final RecordsReading reading = await recordsAt(
      context,
      access: access,
      token: token.value ?? '',
      zoneId: zoneId,
      type: 'A',
      fqdn: fqdn,
    );
    if (reading case RecordsUnreadable(:final String because)) {
      return RecordRefused(because);
    }
    final List<DnsRecord> records = (reading as RecordsHeld).records;
    if (records.length > 1) {
      return RecordRefused(
        '${records.length} address records stand at $fqdn (${records.map((DnsRecord r) => r.content).join(', ')}) '
        '— this step keeps exactly one, and overwriting one of several would dismantle whatever '
        'arrangement put them there; remove the extras by hand first',
      );
    }
    final Map<String, Object?> body = recordBody(
      type: 'A',
      name: fqdn,
      content: address,
      proxied: proxied,
    );
    if (records.isEmpty) {
      return RecordWrite(zoneId: zoneId, body: body);
    }
    final DnsRecord held = records.single;
    if (held.content == address && (held.proxied ?? false) == proxied) {
      return RecordSettled('$fqdn already answers $address (proxied: $proxied)');
    }
    return RecordWrite(
      zoneId: zoneId,
      recordId: held.id,
      before: '${held.content} (proxied: ${held.proxied})',
      body: body,
    );
  }

  @override
  Future<CheckResult> check(StepContext context) async => switch (await _decide(context)) {
    RecordRefused(:final String because) => CheckResult.blocked(because),
    RecordSettled(:final String because) => CheckResult.satisfied(because),
    RecordWrite() => const CheckResult.ready(),
  };

  @override
  Future<StepPlan> plan(StepContext context) async => switch (await _decide(context)) {
    RecordRefused(:final String because) => StepPlan.nothing(because),
    RecordSettled(:final String because) => StepPlan.nothing(because),
    final RecordWrite write => StepPlan.request(
      write.method,
      '${access.apiUrl}/zones/${write.zoneId}/dns_records${write.recordId == null ? '' : '/${write.recordId}'}',
      body:
          '${write.before.isEmpty ? '(absent)' : write.before} -> ${write.body['content']} '
          '(proxied: ${write.body['proxied']})',
    ),
  };

  @override
  Future<CapturedRecord> capture(StepContext context) async {
    final String? fqdn = answeredText(context, fqdnAnswer);
    if (fqdn == null) {
      throw StateError(missingAnswerRefusal(fqdnAnswer, 'the name the record answers under'));
    }
    return captureRecordAt(context, access: access, type: 'A', fqdn: fqdn);
  }

  @override
  Future<void> apply(StepContext context) async {
    switch (await _decide(context)) {
      case RecordRefused(:final String because):
        throw StateError(because);
      case RecordSettled():
        return;
      case final RecordWrite write:
        final CloudflareToken token = await access.tokenFrom(context);
        await writeRecord(
          context,
          access: access,
          token: token.value ?? '',
          zoneId: write.zoneId,
          recordId: write.recordId,
          body: write.body,
        );
    }
  }

  @override
  Future<void> undo(StepContext context, CapturedRecord captured) =>
      restoreRecord(context, access: access, captured: captured);
}
