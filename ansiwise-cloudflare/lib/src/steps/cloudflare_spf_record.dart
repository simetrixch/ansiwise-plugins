import 'package:ansiwise_core/ansiwise_core.dart';

import 'cloudflare_api.dart';

/// Authorises one host to send mail for an apex, by MERGING it into the apex's one SPF
/// record — never by adding a second one.
///
/// **Why merging is the whole design and not a nicety.** SPF's own standard allows a domain exactly
/// one `v=spf1` record; a receiver that finds two answers a permanent error, and mail from that
/// domain starts failing AT THE RECEIVING END, silently, for every sender the domain has — the ones
/// that were working included. The apex of a live domain routinely belongs to somebody else's mail
/// service already, so the existing record is somebody's production mail. This step therefore:
///
/// - inserts `a:<host>` into the ONE existing record, directly before its trailing
///   all-mechanism, keeping the qualifier and every mechanism already there — another service's
///   `include:` lines are exactly what must survive;
/// - creates a fresh record only where none exists at all;
/// - and REFUSES the domain outright when two or more `v=spf1` records already stand there. Two
///   records are already the permanent error; "repairing" them would mean choosing whose mail
///   keeps working, and that is not a machine's call. The refusal names every one of them.
///
/// **The all-mechanism is only ever WRITTEN into a fresh record.** An existing record's policy —
/// `-all`, `~all`, whatever the domain's owner chose — is theirs, and a merge keeps it letter for
/// letter.
final class CloudflareSpfRecord extends ReversibleStep<CapturedRecord> {
  /// Merges the host in the answer named by [hostAnswer] into the SPF record of the apex in
  /// the answer named by [apexAnswer], optionally replacing an address in [replacesAddressAnswer].
  const CloudflareSpfRecord({
    required this.access,
    required this.apexAnswer,
    required this.hostAnswer,
    this.replacesAddressAnswer,
    required this.allMechanism,
  });

  /// Builds the step from what the program gave it.
  factory CloudflareSpfRecord.fromArguments(Arguments arguments) => CloudflareSpfRecord(
    access: CloudflareAccess.fromArguments(arguments),
    apexAnswer: arguments.text('apex_answer'),
    hostAnswer: arguments.text('host_answer'),
    replacesAddressAnswer: arguments.optionalText('replaces_address_answer'),
    allMechanism: arguments.text('all_mechanism'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ...CloudflareAccess.arguments,
    ArgumentSpec(
      name: 'apex_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the domain mail is sent AS — the apex whose one SPF '
          'record this merges into. Named rather than written, because a run is what knows which '
          'installation this is',
    ),
    ArgumentSpec(
      name: 'host_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer holding the host name the mail leaves by — what the merged '
          'record newly authorises, as `a:<host>`, or as the bare `a` when the host is the apex '
          'itself. Named by host, so a change of the host\'s address never touches the record',
    ),
    ArgumentSpec(
      name: 'replaces_address_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer holding an IPv4 address the record may still authorise as '
          '`ip4:<address>`; that one mechanism is replaced by the host\'s, and every other '
          'mechanism stays',
    ),
    ArgumentSpec(
      name: 'all_mechanism',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: '-all',
      allowed: <String>['-all', '~all', '?all', '+all'],
      describes:
          'how a FRESH record closes — what receivers do with senders the record does not '
          'authorise. Only a record created from nothing carries this; an existing record keeps '
          'its own closing mechanism untouched',
    ),
  ];

  /// Where the API and the token are found.
  final CloudflareAccess access;

  /// The name of the answer holding the apex.
  final String apexAnswer;

  /// The name of the answer holding the host.
  final String hostAnswer;

  /// The name of the answer holding an IPv4 address to replace, if any.
  final String? replacesAddressAnswer;

  /// How a fresh record closes; an existing record keeps its own.
  final String allMechanism;

  /// One decision for check, plan and apply, so the three cannot drift apart.
  Future<RecordDecision> _decide(StepContext context) async {
    final CloudflareToken token = await access.tokenFrom(context);
    if (token.refusal case final String refusal) {
      return RecordRefused(refusal);
    }
    final String? apex = answeredText(context, apexAnswer);
    if (apex == null) {
      return RecordRefused(missingAnswerRefusal(apexAnswer, 'the domain mail is sent as'));
    }
    final String? host = answeredText(context, hostAnswer);
    if (host == null) {
      return RecordRefused(missingAnswerRefusal(hostAnswer, 'the host the mail leaves by'));
    }
    if (!isDnsHostName(host)) {
      return RecordRefused(
        '"$hostAnswer" holds "$host", which is not a host name — merged into an SPF '
        'record it would authorise nothing and still change a live mail policy',
      );
    }
    final String? replacesAddress;
    if (replacesAddressAnswer case final String answerName) {
      replacesAddress = answeredText(context, answerName);
      if (replacesAddress == null) {
        return RecordRefused(
          missingAnswerRefusal(answerName, 'the IPv4 address the record replaces'),
        );
      }
      if (!isCidr('$replacesAddress/32')) {
        return RecordRefused(
          '"$answerName" holds "$replacesAddress", which is not an IPv4 address — merged into an SPF '
          'record it would replace nothing and still change a live mail policy',
        );
      }
    } else {
      replacesAddress = null;
    }
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
      fqdn: apex,
    );
    if (reading case RecordsUnreadable(:final String because)) {
      return RecordRefused(because);
    }
    final List<DnsRecord> spf = <DnsRecord>[
      for (final DnsRecord record in (reading as RecordsHeld).records)
        if (isSpfContent(dechunkedTxt(record.content))) record,
    ];
    if (spf.length >= 2) {
      return RecordRefused(
        '$apex carries ${spf.length} v=spf1 records at once — '
        '${spf.map((DnsRecord r) => '"${dechunkedTxt(r.content)}"').join(' and ')}. That is '
        'already the permanent error receivers fail this domain\'s mail on, and folding or '
        'choosing between them would decide whose mail keeps working. Nothing is written here '
        'until a hand removes one',
      );
    }
    final String mechanism = spfMechanism(apex, host);
    if (spf.isEmpty) {
      return RecordWrite(
        zoneId: zoneId,
        body: recordBody(type: 'TXT', name: apex, content: spfFresh(allMechanism, mechanism)),
      );
    }
    final DnsRecord held = spf.single;
    final String current = dechunkedTxt(held.content);
    final String? merged = spfMerged(current, mechanism, replacesAddress: replacesAddress);
    final String foreign = spfForeignMechanisms(
      current,
      mechanism,
      replacesAddress: replacesAddress,
    );
    if (merged == null) {
      return RecordSettled(
        '$apex already authorises $mechanism'
        '${foreign.isEmpty ? '' : ', beside $foreign which stays as it is'}',
      );
    }
    return RecordWrite(
      zoneId: zoneId,
      recordId: held.id,
      before: current,
      body: recordBody(type: 'TXT', name: apex, content: merged),
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
      throw StateError(missingAnswerRefusal(apexAnswer, 'the domain mail is sent as'));
    }
    return captureRecordAt(
      context,
      access: access,
      type: 'TXT',
      fqdn: apex,
      owns: (DnsRecord record) => isSpfContent(dechunkedTxt(record.content)),
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
  Future<void> undo(StepContext context, CapturedRecord captured) => restoreRecord(
    context,
    access: access,
    captured: captured,
    owns: (DnsRecord record) => isSpfContent(dechunkedTxt(record.content)),
  );
}

/// Whether [host] is a valid lowercase DNS host name.
///
/// Must consist of at least two labels separated by dots, each containing only lowercase
/// alphanumeric characters and hyphens (`a-z0-9-`), with no leading or trailing hyphen.
/// An IPv4 address is not a host name.
bool isDnsHostName(String host) {
  if (isCidr('$host/32')) {
    return false;
  }
  final List<String> labels = host.split('.');
  if (labels.length < 2) {
    return false;
  }
  for (final String label in labels) {
    if (!_dnsLabel.hasMatch(label)) {
      return false;
    }
  }
  if (_allDigits.hasMatch(labels.last)) {
    return false;
  }
  return true;
}

final RegExp _dnsLabel = RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$');
final RegExp _allDigits = RegExp(r'^[0-9]+$');

/// Whether a de-chunked TXT value is an SPF record.
///
/// The version term is the exact word `v=spf1`, alone or followed by mechanisms — a value merely
/// beginning with those characters is not one, and counting it toward the two-record refusal would
/// refuse a domain over something receivers never read as SPF.
bool isSpfContent(String content) => content == 'v=spf1' || content.startsWith('v=spf1 ');

/// The SPF mechanism authorising [host] for [apex] — bare `a` when [host] is the apex itself,
/// else `a:[host]`.
String spfMechanism(String apex, String host) => host == apex ? 'a' : 'a:$host';

/// Whether [content] already lists [mechanism], token-aware.
///
/// Padded with spaces on both sides so `a` never matches inside `a:mail.example.org`, and
/// `a:host` never matches as a prefix of `a:host-2.example.org`.
bool spfListsMechanism(String content, String mechanism) => ' $content '.contains(' $mechanism ');

/// [content] with [mechanism] merged in, optionally replacing [replacesAddress], or null where
/// nothing changes.
///
/// When [replacesAddress] is given and [content] lists `ip4:[replacesAddress]` (token-aware), that
/// token is replaced by [mechanism], or dropped when [mechanism] is already listed.
///
/// Otherwise, when [mechanism] is already listed, null is returned so nothing is rewritten.
///
/// Otherwise, [mechanism] is inserted directly BEFORE the trailing all-mechanism, so the record's
/// own closing policy — qualifier included — stays the last word. A record with no all-mechanism
/// gets [mechanism] appended. Pure text surgery: every other mechanism already in the record
/// survives byte for byte.
String? spfMerged(String content, String mechanism, {String? replacesAddress}) {
  if (replacesAddress != null && ' $content '.contains(' ip4:$replacesAddress ')) {
    final List<String> tokens = content.split(_spaces);
    if (spfListsMechanism(content, mechanism)) {
      tokens.removeWhere((String t) => t == 'ip4:$replacesAddress');
      return tokens.join(' ');
    }
    final int index = tokens.indexOf('ip4:$replacesAddress');
    tokens[index] = mechanism;
    tokens.removeWhere((String t) => t == 'ip4:$replacesAddress');
    return tokens.join(' ');
  }
  if (spfListsMechanism(content, mechanism)) {
    return null;
  }
  final RegExpMatch? trailing = _trailingAll.firstMatch(content);
  if (trailing == null) {
    return '$content $mechanism';
  }
  return '${trailing.group(1)}$mechanism ${trailing.group(2)}';
}

/// A fresh SPF record authorising only [mechanism], closed by [allMechanism].
String spfFresh(String allMechanism, String mechanism) => 'v=spf1 $mechanism $allMechanism';

/// The mechanisms of [content] that belong to OTHER senders, as one space-joined text.
///
/// Everything that is not the version term, not [mechanism], not `ip4:[replacesAddress]` (when
/// given) and not the trailing all-mechanism — on a live domain typically another mail service's
/// `include:` lines. Non-empty means the record also authorises senders this run does not manage,
/// which is what a merge exists to preserve and what the operator is told is being kept.
String spfForeignMechanisms(String content, String mechanism, {String? replacesAddress}) {
  final List<String> foreign = <String>[];
  for (final String token in content.split(_spaces)) {
    if (token.isEmpty ||
        token == 'v=spf1' ||
        token == mechanism ||
        (replacesAddress != null && token == 'ip4:$replacesAddress')) {
      continue;
    }
    if (_allMechanism.hasMatch(token)) {
      continue;
    }
    foreign.add(token);
  }
  return foreign.join(' ');
}

final RegExp _spaces = RegExp(r'\s+');
final RegExp _allMechanism = RegExp(r'^[-~?+]?all$');
final RegExp _trailingAll = RegExp(r'^(.*\s)([-~?+]?all)\s*$');
