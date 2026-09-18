import 'package:ansiwise_core/ansiwise_core.dart';

import 'cloudflare_api.dart';

/// Keeps every name under an installation's own name answering what that name answers: one CNAME
/// record at `*.<fqdn>` whose content is `<fqdn>`.
///
/// **A wildcard and never an address.** Every name under `<fqdn>` is the machine's, and the
/// machine's address is what its own record says. A wildcard written as an address would be a
/// second statement of that address, and the two would part the day the machine moves; a CNAME
/// follows the record, so whatever reads the machine's address off it and whatever resolves a name
/// under it agree by construction.
///
/// **Upsert by (name, type), never a blind creation and never a delete-all**, exactly as the address
/// record: the slot is read first, a record that is already right is left alone, one that differs is
/// REPLACED with the full body, one that is missing is created. Proxied is off and part of the
/// desired state: a proxied wildcard answers the service's own addresses, and a certificate
/// challenge for a name under it never reaches this machine.
///
/// **More than one record at the wildcard is a refusal, not a choice.** Several records there mean
/// somebody arranged something this step does not understand, and picking one to overwrite would
/// dismantle it. The refusal names what stands there, and a hand decides.
final class CloudflareWildcardRecord extends ReversibleStep<CapturedRecord> {
  /// Keeps `*.<name>` a CNAME to the name in the answer named by [fqdnAnswer].
  const CloudflareWildcardRecord({required this.access, required this.fqdnAnswer});

  /// Builds the step from what the program gave it.
  factory CloudflareWildcardRecord.fromArguments(Arguments arguments) => CloudflareWildcardRecord(
    access: CloudflareAccess.fromArguments(arguments),
    fqdnAnswer: arguments.text('fqdn_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...CloudflareAccess.arguments,
    ArgumentSpec(
      name: 'fqdn_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the installation\'s own name — the wildcard stands one '
          'label above it and answers with it. Named rather than written, because a run is what '
          'knows which installation this is',
    ),
  ];

  /// Where the API and the token are found.
  final CloudflareAccess access;

  /// The name of the answer holding the installation's own name.
  final String fqdnAnswer;

  /// The record type this step keeps.
  static const String type = 'CNAME';

  /// The wildcard one label above [fqdn].
  static String wildcardOf(String fqdn) => '*.$fqdn';

  /// One decision for check, plan and apply, so the three cannot drift apart.
  Future<RecordDecision> _decide(StepContext context) async {
    final CloudflareToken token = await access.tokenFrom(context);
    if (token.refusal case final String refusal) {
      return RecordRefused(refusal);
    }
    final String? fqdn = answeredText(context, fqdnAnswer);
    if (fqdn == null) {
      return RecordRefused(missingAnswerRefusal(fqdnAnswer, 'the name the wildcard stands above'));
    }
    // The zone is walked from the name itself: a wildcard is never a zone, and asking for it
    // would only spend a request on an answer known in advance.
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
    final String name = wildcardOf(fqdn);
    final RecordsReading reading = await recordsAt(
      context,
      access: access,
      token: token.value ?? '',
      zoneId: zoneId,
      type: type,
      fqdn: name,
    );
    if (reading case RecordsUnreadable(:final String because)) {
      return RecordRefused(because);
    }
    final List<DnsRecord> records = (reading as RecordsHeld).records;
    if (records.length > 1) {
      return RecordRefused(
        '${records.length} alias records stand at $name (${records.map((DnsRecord r) => r.content).join(', ')}) '
        '— this step keeps exactly one, and overwriting one of several would dismantle whatever '
        'arrangement put them there; remove the extras by hand first',
      );
    }
    final Map<String, Object?> body = recordBody(
      type: type,
      name: name,
      content: fqdn,
      proxied: false,
    );
    if (records.isEmpty) {
      return RecordWrite(zoneId: zoneId, body: body);
    }
    final DnsRecord held = records.single;
    if (held.content == fqdn && !(held.proxied ?? false)) {
      return RecordSettled('$name already answers what $fqdn answers (proxied: false)');
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
          '${write.before.isEmpty ? '(absent)' : write.before} -> ${write.body['content']} (proxied: false)',
    ),
  };

  @override
  Future<CapturedRecord> capture(StepContext context) async {
    final String? fqdn = answeredText(context, fqdnAnswer);
    if (fqdn == null) {
      throw StateError(missingAnswerRefusal(fqdnAnswer, 'the name the wildcard stands above'));
    }
    return captureRecordAt(context, access: access, type: type, fqdn: wildcardOf(fqdn));
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
