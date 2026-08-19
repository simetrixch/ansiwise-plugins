import 'package:ansiwise_core/ansiwise_core.dart';

import 'cloudflare_api.dart';

/// Publishes an apex's DKIM public key, at the selector name DKIM itself prescribes.
///
/// **The name and the record text are composed HERE, and that is the point of the step.** DKIM
/// fixes both shapes — the key is looked up at `<selector>._domainkey.<apex>` and the record reads
/// `v=DKIM1; h=sha256; k=rsa; p=<key>` — and a program file may not build strings. What is not
/// DKIM's is the selector, the apex and the key, and all three arrive from outside.
///
/// **The key comes out of the hand-filled input, beside the API token, and it is the PUBLIC half.**
/// The `p=` value is what the record itself broadcasts to every receiver on earth, so reading it
/// from the input file is not a secret leaving anywhere. The private half never comes near this
/// package.
///
/// **No key means NO RECORD, said out loud — never a placeholder.** A DKIM record that nothing
/// signs with is worse than none: receivers that find the record expect signatures and fail mail
/// that carries none. So an input whose key variable is still empty satisfies this step with a
/// message saying exactly that, and the record appears on the run after the key does.
final class CloudflareDkimRecord extends ReversibleStep<CapturedRecord> {
  /// Publishes the key in the input variable [publicKeyVariable] for the apex in the answer named
  /// by [apexAnswer], under the selector in the answer named by [selectorAnswer].
  const CloudflareDkimRecord({
    required this.access,
    required this.apexAnswer,
    required this.selectorAnswer,
    required this.publicKeyVariable,
  });

  /// Builds the step from what the program gave it.
  factory CloudflareDkimRecord.fromArguments(Arguments arguments) => CloudflareDkimRecord(
    access: CloudflareAccess.fromArguments(arguments),
    apexAnswer: arguments.text('apex_answer'),
    selectorAnswer: arguments.text('selector_answer'),
    publicKeyVariable: arguments.text('public_key_variable'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...CloudflareAccess.arguments,
    ArgumentSpec(
      name: 'apex_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the domain the key signs for — the apex under whose '
          '_domainkey child the record is looked up. Named rather than written, because a run is '
          'what knows which installation this is',
    ),
    ArgumentSpec(
      name: 'selector_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the selector — the label a signature names so a domain '
          'can hold several keys at once. It must be the selector the signer actually writes, or '
          'receivers look the key up at a name that holds nothing',
    ),
    ArgumentSpec(
      name: 'public_key_variable',
      kind: ArgumentKind.text,
      describes:
          'the variable of the hand-filled input that holds the PUBLIC key, as the single-line '
          'base64 the record\'s p= carries. Left empty, no record is published and the step says '
          'so — a record nothing signs with makes receivers fail mail that is otherwise fine',
    ),
  ];

  /// Where the API and the token are found.
  final CloudflareAccess access;

  /// The name of the answer holding the apex.
  final String apexAnswer;

  /// The name of the answer holding the selector.
  final String selectorAnswer;

  /// The variable of the hand-filled input that holds the public key.
  final String publicKeyVariable;

  /// One decision for check, plan and apply, so the three cannot drift apart.
  Future<RecordDecision> _decide(StepContext context) async {
    final CloudflareToken token = await access.tokenFrom(context);
    if (token.refusal case final String refusal) {
      return RecordRefused(refusal);
    }
    final String? apex = answeredText(context, apexAnswer);
    if (apex == null) {
      return RecordRefused(missingAnswerRefusal(apexAnswer, 'the domain the key signs for'));
    }
    final String? selector = answeredText(context, selectorAnswer);
    if (selector == null) {
      return RecordRefused(
        missingAnswerRefusal(selectorAnswer, 'the selector the key is looked up under'),
      );
    }
    final String path = access.secretsPath(context);
    final String key = keyValueAssignments(await context.files.read(path))[publicKeyVariable] ?? '';
    if (key.isEmpty || stillUnfilled(key)) {
      return RecordSettled(
        '$publicKeyVariable is empty in $path, so there is no signing key to publish — a DKIM '
        'record nothing signs with makes receivers fail mail that is otherwise fine, so none is '
        'written until the key stands there',
      );
    }
    if (!_base64Line.hasMatch(key)) {
      return RecordRefused(
        '$publicKeyVariable in $path is not a single line of base64, and the p= of a DKIM record '
        'is exactly that — published as it stands, every receiver would fail the signature',
      );
    }
    final String name = '$selector._domainkey.$apex';
    final String content = 'v=DKIM1; h=sha256; k=rsa; p=$key';
    final ZoneLookup zone = await zoneFor(
      context,
      access: access,
      token: token.value ?? '',
      fqdn: apex,
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
      type: 'TXT',
      fqdn: name,
    );
    if (reading case RecordsUnreadable(:final String because)) {
      return RecordRefused(because);
    }
    final List<DnsRecord> records = (reading as RecordsHeld).records;
    if (records.length > 1) {
      return RecordRefused(
        '${records.length} TXT records stand at $name — a selector name holds one key, and '
        'overwriting one of several would leave receivers finding whichever survives; remove the '
        'extras by hand first',
      );
    }
    final Map<String, Object?> body = recordBody(type: 'TXT', name: name, content: content);
    if (records.isEmpty) {
      return RecordWrite(zoneId: zoneId, body: body);
    }
    final DnsRecord held = records.single;
    if (dechunkedTxt(held.content) == content) {
      return RecordSettled('$name already carries this key');
    }
    return RecordWrite(
      zoneId: zoneId,
      recordId: held.id,
      before: dechunkedTxt(held.content),
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
      body: '${write.before.isEmpty ? '(absent)' : write.before} -> ${write.body['content']}',
    ),
  };

  @override
  Future<CapturedRecord> capture(StepContext context) async {
    final String? apex = answeredText(context, apexAnswer);
    final String? selector = answeredText(context, selectorAnswer);
    if (apex == null || selector == null) {
      throw StateError(
        missingAnswerRefusal(
          apex == null ? apexAnswer : selectorAnswer,
          'part of the name the key is looked up under',
        ),
      );
    }
    return captureRecordAt(
      context,
      access: access,
      type: 'TXT',
      fqdn: '$selector._domainkey.$apex',
    );
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

/// One unbroken line of base64, which is the only thing a DKIM `p=` may carry.
final RegExp _base64Line = RegExp(r'^[A-Za-z0-9+/]+=*$');
