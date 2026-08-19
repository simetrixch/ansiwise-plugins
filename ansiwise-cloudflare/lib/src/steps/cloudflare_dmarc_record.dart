import 'package:ansiwise_core/ansiwise_core.dart';

import 'cloudflare_api.dart';

/// Publishes an apex's DMARC policy, at the name and in the text DMARC itself prescribes.
///
/// **Composed HERE for the same reason the DKIM record is.** DMARC fixes the shape — the policy is
/// looked up at `_dmarc.<apex>` and reads `v=DMARC1; p=<policy>; rua=mailto:<mailbox>` — and a
/// program file may not build strings. Which apex, which policy and which mailbox are the
/// installation's, and arrive from outside.
///
/// **The policy is one of the three words DMARC defines, checked here as well as at the form.** The
/// program's answer declaration already offers only the legal three; the step refuses anything else
/// all the same, because a record carrying a word receivers do not know is read as `p=none` by some
/// and as unparseable by others — a policy that differs by receiver is worse than either.
final class CloudflareDmarcRecord extends ReversibleStep<CapturedRecord> {
  /// Publishes the policy in the answer named by [policyAnswer] for the apex in the answer named by
  /// [apexAnswer], with reports going to the mailbox in the answer named by [mailboxAnswer].
  const CloudflareDmarcRecord({
    required this.access,
    required this.apexAnswer,
    required this.policyAnswer,
    required this.mailboxAnswer,
  });

  /// Builds the step from what the program gave it.
  factory CloudflareDmarcRecord.fromArguments(Arguments arguments) => CloudflareDmarcRecord(
    access: CloudflareAccess.fromArguments(arguments),
    apexAnswer: arguments.text('apex_answer'),
    policyAnswer: arguments.text('policy_answer'),
    mailboxAnswer: arguments.text('mailbox_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...CloudflareAccess.arguments,
    ArgumentSpec(
      name: 'apex_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the domain the policy speaks for — the apex under whose '
          '_dmarc child the record is looked up. Named rather than written, because a run is what '
          'knows which installation this is',
    ),
    ArgumentSpec(
      name: 'policy_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding what receivers do with mail that fails alignment: none, '
          'quarantine or reject — DMARC\'s own three words, and nothing else',
    ),
    ArgumentSpec(
      name: 'mailbox_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the mailbox receivers send their aggregate reports to — '
          'where the operator learns who is sending as this domain',
    ),
  ];

  /// Where the API and the token are found.
  final CloudflareAccess access;

  /// The name of the answer holding the apex.
  final String apexAnswer;

  /// The name of the answer holding the policy word.
  final String policyAnswer;

  /// The name of the answer holding the report mailbox.
  final String mailboxAnswer;

  /// The three words DMARC defines for `p=`, and the only ones a record may carry.
  static const List<String> policies = <String>['none', 'quarantine', 'reject'];

  /// One decision for check, plan and apply, so the three cannot drift apart.
  Future<RecordDecision> _decide(StepContext context) async {
    final CloudflareToken token = await access.tokenFrom(context);
    if (token.refusal case final String refusal) {
      return RecordRefused(refusal);
    }
    final String? apex = answeredText(context, apexAnswer);
    if (apex == null) {
      return RecordRefused(missingAnswerRefusal(apexAnswer, 'the domain the policy speaks for'));
    }
    final String? policy = answeredText(context, policyAnswer);
    if (policy == null) {
      return RecordRefused(
        missingAnswerRefusal(policyAnswer, 'what receivers do with mail that fails alignment'),
      );
    }
    if (!policies.contains(policy)) {
      return RecordRefused(
        '"$policyAnswer" holds "$policy", and a DMARC policy is one of ${policies.join(', ')} — '
        'published as it stands, receivers would each read it as something different',
      );
    }
    final String? mailbox = answeredText(context, mailboxAnswer);
    if (mailbox == null) {
      return RecordRefused(
        missingAnswerRefusal(mailboxAnswer, 'the mailbox the aggregate reports go to'),
      );
    }
    if (!ValueShape.mailbox.holds(mailbox)) {
      return RecordRefused(
        '"$mailboxAnswer" holds "$mailbox", which is not a mailbox — the reports receivers send '
        'would go nowhere and nobody would ever learn who sends as $apex',
      );
    }
    final String name = '_dmarc.$apex';
    final String content = 'v=DMARC1; p=$policy; rua=mailto:$mailbox';
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
        '${records.length} TXT records stand at $name — receivers finding several DMARC records '
        'treat the domain as having none, and overwriting one would not mend that; remove the '
        'extras by hand first',
      );
    }
    final Map<String, Object?> body = recordBody(type: 'TXT', name: name, content: content);
    if (records.isEmpty) {
      return RecordWrite(zoneId: zoneId, body: body);
    }
    final DnsRecord held = records.single;
    if (dechunkedTxt(held.content) == content) {
      return RecordSettled('$name already carries this policy');
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
    if (apex == null) {
      throw StateError(missingAnswerRefusal(apexAnswer, 'the domain the policy speaks for'));
    }
    return captureRecordAt(context, access: access, type: 'TXT', fqdn: '_dmarc.$apex');
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
