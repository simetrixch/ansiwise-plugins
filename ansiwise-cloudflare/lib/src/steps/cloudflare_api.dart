/// Reaching the Cloudflare v4 API, and reading the file one installation's token stands in.
///
/// **The token rides `Authorization: Bearer`, and that is a decision about the record.** It is the
/// header Cloudflare's own token authentication uses, and it is a name the framework's redactor
/// removes on sight — so the token cannot reach the record even on a run where nobody registered
/// its value as a secret.
///
/// **The API's address has a default and the zone never does.** One is a fact of the tool — the
/// service answers at one public address for everybody — and the other is a fact of one
/// installation. So the address may be left unsaid and the zone is WALKED: the API is asked for the
/// exact name, and when that is not a zone the leftmost label is stripped and it is asked again.
/// That routes `m1.example.com` to the `example.com` zone with no name written anywhere, and it is
/// the API itself that answers, not a guess about where registrable domains end.
///
/// **An answer that cannot be understood is never read as an empty zone.** Reading a failure as
/// "nothing is there" is what makes a tool write over what IS there; every reading in this file has
/// a third case that refuses, and the steps turn it into a blocked check rather than into work.
library;

import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// How long any one call to the API may take before the run gives up on it.
///
/// Explicit because the default is to wait forever, and an endpoint that accepts the connection and
/// then hangs would otherwise turn one slow dependency into a run nobody can tell from a working
/// one.
const Duration cloudflareTimeout = Duration(seconds: 30);

/// Where the Cloudflare v4 API answers for everybody.
///
/// A constant of the TOOL and not of any installation: the service is reached at one public
/// address. It stands here once, as the default of the `api_url` argument, so a program row says
/// nothing about it — and a test, or an installation that reaches the API through something of its
/// own, may still say otherwise.
const String cloudflareApiUrl = 'https://api.cloudflare.com/client/v4';

/// Where one installation's API token stands, and where the API itself answers.
///
/// The names are declared ONCE, in [arguments], and every step of this package spreads that list
/// into its own — so the family cannot disagree about a name. What stands UNDER the names is never
/// an argument: the token is a credential and lives in the one hand-filled input of the
/// installation, read here by the variable name a row states and never printed.
///
/// **Why the token is read from a file and not taken as an answer.** An answer travels with every
/// run and is typed by whoever triggers it; the hand-filled input is filled once, stands on the
/// machine the run reaches, and is already where the installation keeps this credential for its
/// other readers. One home, no retyping, and no second copy that can drift.
final class CloudflareAccess {
  /// The access exactly as a program row describes it.
  const CloudflareAccess({
    required this.apiUrl,
    required this.repository,
    required this.secrets,
    required this.tokenVariable,
    this.runAnswer,
  });

  /// Builds the access from what the program gave the step carrying it.
  factory CloudflareAccess.fromArguments(Arguments arguments) => CloudflareAccess(
    apiUrl: arguments.text('api_url'),
    repository: arguments.text('repository'),
    secrets: arguments.text('secrets_path'),
    tokenVariable: arguments.text('token_variable'),
    runAnswer: arguments.optionalText('run_answer'),
  );

  /// The arguments every step of this package declares.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'api_url',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: cloudflareApiUrl,
      describes:
          'where the v4 API answers. The default is the public address the service itself is at, '
          'which is why this is the one value of the family a row may leave unsaid',
    ),
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          'the checkout this installation runs from, which carries the hand-filled input the API '
          'token is read out of',
    ),
    ArgumentSpec(
      name: 'secrets_path',
      kind: ArgumentKind.text,
      describes:
          'where the one hand-filled input of this installation stands, under the checkout at '
          'repository — it may carry the run_answer slot, and this run\'s value for it fills that '
          'place',
    ),
    ArgumentSpec(
      name: 'token_variable',
      kind: ArgumentKind.text,
      describes:
          'the variable of the hand-filled input that holds the API token — never the token '
          'itself. The token needs leave to read the zone and edit its records, and nothing wider',
    ),
    // The ONE axis a product may run the same layout along more than once, and the reason it is
    // named rather than known: the API has no such axis. A product with three environments keeps
    // one hand-filled input per environment, one with regions keeps the same per region, and a
    // product with neither keeps none at all — so what the axis is CALLED is the product's, and a
    // name written into this package would make every vendor carry that one.
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name — write '
          '"stage" here and every "<stage>" in the secrets path is filled with this run\'s stage. '
          'Leave it off where the product has no such axis',
    ),
  ];

  /// Where the v4 API answers.
  final String apiUrl;

  /// The checkout this installation runs from.
  final String repository;

  /// Where the hand-filled input stands under the checkout, with the run answer's place marked.
  final String secrets;

  /// The variable of the hand-filled input that holds the API token.
  final String tokenVariable;

  /// The name of the answer whose value fills the slot spelled with that same name, or null where
  /// the product running these steps has no such axis.
  final String? runAnswer;

  /// The text that stands where this run's own value for [runAnswer] belongs, or null where there
  /// is no such answer.
  ///
  /// Derived from the name rather than declared beside it, so the slot and the answer cannot come
  /// apart: a program that renames the answer renames the slot in the same act.
  String? get runSlot => runAnswer == null ? null : '<$runAnswer>';

  /// [text] with this run's own value for [runAnswer] where the slot marks it.
  ///
  /// Text carrying no slot, an access naming no answer, and a run that does not hold the answer all
  /// come back unchanged — the last of them so the slot is still visible in whatever refusal
  /// reports the text, rather than being replaced by an empty string nobody could see.
  String runAnswerFilled(StepContext context, String text) {
    final String? slot = runSlot;
    final String? answer = runAnswer;
    if (slot == null || answer == null || !text.contains(slot) || !context.answers.has(answer)) {
      return text;
    }
    return text.replaceAll(slot, context.answers.text(answer));
  }

  /// Where the one hand-filled input of this installation is, under the checkout.
  String secretsPath(StepContext context) => '$repository/${runAnswerFilled(context, secrets)}';

  /// Reads the API token out of the hand-filled input, or says why it cannot.
  ///
  /// Every step of this package needs the same answers about the same file — is it there, does it
  /// parse, does it carry the token — and each is a refusal an operator acts on differently.
  /// Returned as a value rather than thrown, so a step turns it into a blocked check and the
  /// program's declared failure policy decides what that costs. The token itself is never logged
  /// and never part of any refusal.
  Future<CloudflareToken> tokenFrom(StepContext context) async {
    final String path = secretsPath(context);
    final String? slot = _leftoverSlot.firstMatch(path)?.group(0);
    if (slot != null) {
      return CloudflareToken.unreadable(
        '$path still carries $slot, and nothing in this run holds that name — the row that names '
        'the answer filling it is where that is decided',
      );
    }
    if (!await context.files.exists(path)) {
      return CloudflareToken.unreadable(
        '$path is not on this host, and it is the one file an operator fills in — the API token '
        'is read out of it',
      );
    }
    final String content = await context.files.read(path);
    if (content.contains('\r')) {
      return CloudflareToken.unreadable(
        '$path carries a carriage return, and a credential read out of it would carry one too — '
        'rewrite the file with unix line endings before this runs again',
      );
    }
    final String value = keyValueAssignments(content)[tokenVariable] ?? '';
    if (value.isEmpty) {
      return CloudflareToken.unreadable(
        '$tokenVariable is empty in $path, and it is where the API token stands. Put a token '
        'there with leave to read the zone and edit its records — nothing account-wide, and '
        'nothing on any other zone',
      );
    }
    if (stillUnfilled(value)) {
      return CloudflareToken.unreadable(
        '$tokenVariable in $path still holds the text that marks it unfilled',
      );
    }
    return CloudflareToken.read(value);
  }
}

/// Anything at all between angle brackets, which is what an unfilled slot looks like.
final RegExp _leftoverSlot = RegExp('<[^<>]*>');

/// The API token a step was able to read, or why it could not.
final class CloudflareToken {
  /// Records that the token was read.
  const CloudflareToken.read(this.value) : refusal = null;

  /// Records that it could not be read, because [refusal].
  const CloudflareToken.unreadable(this.refusal) : value = null;

  /// The token, or null when there is none to be had.
  final String? value;

  /// Why there is none, or null when there is.
  final String? refusal;
}

/// The values of [content] read as a file of `KEY=value` lines.
///
/// The hand-filled input of an installation is written this way, and it is read into an explicit
/// map here rather than executed: a file that can only be read by running it is a file that can run
/// anything.
Map<String, String> keyValueAssignments(String content) {
  final Map<String, String> values = <String, String>{};
  for (final String raw in const LineSplitter().convert(content)) {
    final String line = raw.trim().startsWith('export ') ? raw.trim().substring(7) : raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int equals = line.indexOf('=');
    if (equals <= 0) {
      continue;
    }
    final String name = line.substring(0, equals).trim();
    if (name.isEmpty) {
      continue;
    }
    values[name] = _unquoted(line.substring(equals + 1).trim());
  }
  return values;
}

/// Whether [value] is still the text that marks a value nobody has filled in.
///
/// An angle-bracketed name is how an example input says "fill this in", and no value this package
/// reads can legitimately carry one: an API token's alphabet has no angle bracket in it.
bool stillUnfilled(String value) => value.contains('<') && value.contains('>');

String _unquoted(String value) {
  if (value.length >= 2) {
    final String first = value[0];
    if ((first == '"' || first == "'") && value.endsWith(first)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}

/// A request that reads [url].
///
/// A `GET`, so the framework derives on its own that it changes nothing — which is what lets a dry
/// run send it and still be a dry run.
HttpRequest cloudflareGet(String url, {required String token}) =>
    HttpRequest('GET', url, headers: _headers(token), timeout: cloudflareTimeout);

/// A request that sends [body] to [url] with [method].
HttpRequest cloudflareSend(
  String method,
  String url, {
  required String token,
  required Map<String, Object?> body,
}) => HttpRequest(
  method,
  url,
  headers: <String, String>{..._headers(token), 'content-type': 'application/json'},
  body: jsonEncode(body),
  timeout: cloudflareTimeout,
);

/// A request that removes what stands at [url].
HttpRequest cloudflareDelete(String url, {required String token}) =>
    HttpRequest('DELETE', url, headers: _headers(token), timeout: cloudflareTimeout);

Map<String, String> _headers(String token) => <String, String>{'authorization': 'Bearer $token'};

/// What one call to the API actually told us, which is one of TWO things and never a guess.
///
/// The v4 API wraps every answer the same way: a `success` flag, a `result`, and an `errors` list —
/// and it can answer HTTP 200 with `success: false`. So neither the status nor the body alone is
/// read; [resultOf] reads both, and everything that is not an understood success is a refusal
/// carrying the API's own error lines. There is no "absent" case here the way a key-value store has
/// one: a name with no records answers success with an empty list, which IS an answer about the
/// zone.
sealed class CloudflareReading {
  const CloudflareReading();
}

/// The API answered, and this is its `result`.
final class CloudflareResult extends CloudflareReading {
  /// Holds [result], exactly as the answer carried it.
  const CloudflareResult(this.result);

  /// The `result` of the answer — a list for a listing, an object for a single record.
  final Object? result;
}

/// The API answered something no step may act on.
final class CloudflareRefused extends CloudflareReading {
  /// Could not be acted on, [because].
  const CloudflareRefused(this.because);

  /// What was wrong with the answer, in the words a refusal uses.
  final String because;
}

/// What [answer] says about [what], told apart into the two cases.
///
/// The body is decoded here rather than by each caller, because deciding that an answer is
/// UNDERSTANDABLE and deciding what it says are the same act: an answer whose body will not decode
/// is exactly the case that must never pass for an empty zone.
CloudflareReading resultOf(HttpAnswer answer, {required String what}) {
  final Map<String, Object?>? decoded = _decodedObject(answer.body);
  final String apiErrors = _errorLines(decoded);
  if (!answer.ok) {
    return CloudflareRefused(
      '$what answered ${answer.status}$apiErrors — neither what stands there nor that nothing '
      'does, and a step that read it as nothing would write over whatever is there',
    );
  }
  if (decoded == null || decoded['success'] != true) {
    return CloudflareRefused(
      '$what answered ${answer.status} but not success$apiErrors — the API refused the call, and '
      'what stands there is unknown',
    );
  }
  return CloudflareResult(decoded['result']);
}

Map<String, Object?>? _decodedObject(String body) {
  if (body.trim().isEmpty) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return null;
  }
  return decoded is Map<String, Object?> ? decoded : null;
}

/// The API's own `errors` as one readable clause, or nothing where there are none.
String _errorLines(Map<String, Object?>? decoded) {
  final Object? errors = decoded?['errors'];
  if (errors is! List<Object?> || errors.isEmpty) {
    return '';
  }
  final List<String> lines = <String>[
    for (final Object? error in errors)
      if (error is Map<String, Object?>) '[${error['code']}] ${error['message']}',
  ];
  return lines.isEmpty ? '' : ' (${lines.join('; ')})';
}

/// Which zone a name lives in, or why that cannot be known.
sealed class ZoneLookup {
  const ZoneLookup();
}

/// The zone was found, and this is its identifier.
final class ZoneFound extends ZoneLookup {
  /// Records the zone [id] the walked name landed in.
  const ZoneFound(this.id);

  /// The zone's identifier, as every record call addresses it.
  final String id;
}

/// No zone could be resolved, and this says why.
final class ZoneUnknown extends ZoneLookup {
  /// Records that no zone answered, [because].
  const ZoneUnknown(this.because);

  /// What kept the zone from being resolved, in the words a refusal uses.
  final String because;
}

/// The zone [fqdn] lives in, found by asking the API and walking the labels.
///
/// The exact name is asked first; when it is not a zone the leftmost label is stripped and the rest
/// is asked again, down to the last dot. The API is the authority on where the zone boundary is —
/// no list of registrable suffixes is carried here, because such a list is wrong the day after it
/// is written.
Future<ZoneLookup> zoneFor(
  StepContext context, {
  required CloudflareAccess access,
  required String token,
  required String fqdn,
}) async {
  String candidate = fqdn;
  while (candidate.contains('.')) {
    final HttpAnswer answer = await context.http.send(
      cloudflareGet('${access.apiUrl}/zones?name=$candidate&per_page=1', token: token),
    );
    final CloudflareReading reading = resultOf(answer, what: 'asking for the zone $candidate');
    if (reading case CloudflareRefused(:final String because)) {
      return ZoneUnknown(because);
    }
    final Object? result = (reading as CloudflareResult).result;
    if (result is List<Object?> && result.isNotEmpty) {
      final Object? first = result.first;
      final Object? id = first is Map<String, Object?> ? first['id'] : null;
      if (id is String && id.isNotEmpty) {
        return ZoneFound(id);
      }
      return const ZoneUnknown(
        'the API listed a zone without an identifier, which no record call could address',
      );
    }
    candidate = candidate.substring(candidate.indexOf('.') + 1);
  }
  return ZoneUnknown(
    'no zone on this account answers for $fqdn or any suffix of it — the token has to be scoped '
    'to the zone the name lives in, and the zone has to exist there',
  );
}

/// One record as the zone holds it.
final class DnsRecord {
  /// Records one entry of a zone listing.
  const DnsRecord({
    required this.id,
    required this.type,
    required this.name,
    required this.content,
    this.proxied,
  });

  /// The record's identifier, as an update or a removal addresses it.
  final String id;

  /// The record's type, upper case.
  final String type;

  /// The full name the record answers under.
  final String name;

  /// The record's value, exactly as the API returned it.
  final String content;

  /// Whether the record is proxied, or null for a type that cannot be.
  final bool? proxied;
}

/// The records of one (name, type), or why they cannot be known.
sealed class RecordsReading {
  const RecordsReading();
}

/// The zone answered, and these are the records.
final class RecordsHeld extends RecordsReading {
  /// Holds what stands at the asked name and type.
  const RecordsHeld(this.records);

  /// Every record of exactly that name and type, possibly none.
  final List<DnsRecord> records;
}

/// The zone could not be read, and this says why.
final class RecordsUnreadable extends RecordsReading {
  /// Records that the listing failed, [because].
  const RecordsUnreadable(this.because);

  /// What kept the records from being read, in the words a refusal uses.
  final String because;
}

/// The records of type [type] named EXACTLY [fqdn] in [zoneId].
///
/// The name and type ride the query AND are matched again client-side, so it does not matter
/// whether the account's API treats `name=` as exact or as a prefix — a partial match can never
/// cause a false "exists" or a duplicate.
Future<RecordsReading> recordsAt(
  StepContext context, {
  required CloudflareAccess access,
  required String token,
  required String zoneId,
  required String type,
  required String fqdn,
}) async {
  final HttpAnswer answer = await context.http.send(
    cloudflareGet(
      '${access.apiUrl}/zones/$zoneId/dns_records?type=$type&name=$fqdn&per_page=100',
      token: token,
    ),
  );
  final CloudflareReading reading = resultOf(answer, what: 'listing the $type records of $fqdn');
  if (reading case CloudflareRefused(:final String because)) {
    return RecordsUnreadable(because);
  }
  final Object? result = (reading as CloudflareResult).result;
  if (result is! List<Object?>) {
    return RecordsUnreadable(
      'listing the $type records of $fqdn answered a shape this cannot make sense of, so what '
      'stands there is unknown',
    );
  }
  final List<DnsRecord> records = <DnsRecord>[];
  for (final Object? entry in result) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    final Object? id = entry['id'];
    final Object? name = entry['name'];
    final Object? entryType = entry['type'];
    final Object? content = entry['content'];
    if (id is! String || name != fqdn || entryType != type || content is! String) {
      continue;
    }
    final Object? proxied = entry['proxied'];
    records.add(
      DnsRecord(
        id: id,
        type: type,
        name: fqdn,
        content: content,
        proxied: proxied is bool ? proxied : null,
      ),
    );
  }
  return RecordsHeld(records);
}

/// [raw] as the one text a TXT value is, however the zone stored it.
///
/// The API stores a long TXT value as quoted 255-character chunks and returns it that way — outer
/// quotes, and `" "` where it split. Compared raw, a correct DKIM record reads as drift on every
/// run and is rewritten forever; both sides of every TXT comparison go through here first.
String dechunkedTxt(String raw) {
  String value = raw;
  if (value.startsWith('"')) {
    value = value.substring(1);
  }
  if (value.endsWith('"')) {
    value = value.substring(0, value.length - 1);
  }
  return value.replaceAll('" "', '');
}

/// The body a record is created or replaced with.
///
/// `ttl: 1` is the API's own word for "automatic". [proxied] is included only when passed — a TXT
/// record is not proxiable, and sending the field would be refused.
Map<String, Object?> recordBody({
  required String type,
  required String name,
  required String content,
  bool? proxied,
}) => <String, Object?>{
  'type': type,
  'name': name,
  'content': content,
  'ttl': 1,
  'proxied': ?proxied,
};

/// Writes [body] into [zoneId] — a creation when [recordId] is null, a full replacement otherwise.
///
/// A replacement sends the FULL desired body, so it also self-heals drift a comparison found — a
/// stale address, an accidentally proxied entry — rather than patching one field and leaving the
/// rest to whatever put it there.
Future<void> writeRecord(
  StepContext context, {
  required CloudflareAccess access,
  required String token,
  required String zoneId,
  required Map<String, Object?> body,
  String? recordId,
}) async {
  final String method = recordId == null ? 'POST' : 'PUT';
  final String url = recordId == null
      ? '${access.apiUrl}/zones/$zoneId/dns_records'
      : '${access.apiUrl}/zones/$zoneId/dns_records/$recordId';
  final HttpAnswer answer = await context.http.send(
    cloudflareSend(method, url, token: token, body: body),
  );
  final CloudflareReading reading = resultOf(
    answer,
    what: 'writing the ${body['type']} record ${body['name']}',
  );
  if (reading case CloudflareRefused(:final String because)) {
    throw StateError(because);
  }
}

/// Removes the record [recordId] from [zoneId].
Future<void> removeRecord(
  StepContext context, {
  required CloudflareAccess access,
  required String token,
  required String zoneId,
  required String recordId,
}) async {
  final HttpAnswer answer = await context.http.send(
    cloudflareDelete('${access.apiUrl}/zones/$zoneId/dns_records/$recordId', token: token),
  );
  final CloudflareReading reading = resultOf(answer, what: 'removing the record $recordId');
  if (reading case CloudflareRefused(:final String because)) {
    throw StateError(because);
  }
}

/// What one record slot held before a step touched it, kept so an undo can put it back.
///
/// Read BEFORE the step applies and handed back at undo time, never looked up again: an undo that
/// re-measures the machine measures a machine that has changed since — by this step, by the steps
/// after it, and by whatever went on outside the run.
final class CapturedRecord {
  /// Records what stood there: one record, with everything a restoration writes.
  const CapturedRecord.held({
    required this.zoneId,
    required String this.id,
    required this.type,
    required this.name,
    required String this.content,
    this.proxied,
  });

  /// Records that nothing stood there.
  const CapturedRecord.absent({required this.zoneId, required this.type, required this.name})
    : id = null,
      content = null,
      proxied = null;

  /// The zone the slot is in, kept so the undo does not have to walk for it again.
  final String zoneId;

  /// The record's identifier, or null where nothing stood there.
  final String? id;

  /// The record's type.
  final String type;

  /// The full name of the slot.
  final String name;

  /// What the record held, or null where nothing stood there.
  final String? content;

  /// Whether the record was proxied, or null for a type that cannot be.
  final bool? proxied;

  /// Whether anything stood there at all.
  bool get wasThere => id != null;
}

/// Reads what stands in one record slot, for [CapturedRecord] to keep.
///
/// [owns] narrows the slot where a (name, type) pair legitimately holds records of more than one
/// kind — an apex TXT name holds verifications and policies side by side, and only one of them is
/// this step's. More than one record inside the narrowed slot is a throw, not a choice: this
/// package keeps what it overwrites, and with several there it cannot say which one that is.
Future<CapturedRecord> captureRecordAt(
  StepContext context, {
  required CloudflareAccess access,
  required String type,
  required String fqdn,
  bool Function(DnsRecord record)? owns,
}) async {
  final CloudflareToken token = await access.tokenFrom(context);
  if (token.refusal case final String refusal) {
    throw StateError(refusal);
  }
  final ZoneLookup zone = await zoneFor(
    context,
    access: access,
    token: token.value ?? '',
    fqdn: fqdn,
  );
  if (zone case ZoneUnknown(:final String because)) {
    throw StateError(because);
  }
  final String zoneId = (zone as ZoneFound).id;
  final RecordsReading reading = await recordsAt(
    context,
    access: access,
    token: token.value ?? '',
    zoneId: zoneId,
    type: type,
    fqdn: fqdn,
  );
  if (reading case RecordsUnreadable(:final String because)) {
    throw StateError(because);
  }
  final List<DnsRecord> records = <DnsRecord>[
    for (final DnsRecord record in (reading as RecordsHeld).records)
      if (owns == null || owns(record)) record,
  ];
  if (records.isEmpty) {
    return CapturedRecord.absent(zoneId: zoneId, type: type, name: fqdn);
  }
  if (records.length > 1) {
    throw StateError(
      '${records.length} $type records stand at $fqdn where this step keeps exactly one — with '
      'several there it cannot say which it would be putting back, so nothing is touched',
    );
  }
  final DnsRecord held = records.single;
  return CapturedRecord.held(
    zoneId: zoneId,
    id: held.id,
    type: type,
    name: fqdn,
    content: held.content,
    proxied: held.proxied,
  );
}

/// Puts one record slot back the way [captured] describes it.
///
/// A slot that held a record gets that record's full body written back over whatever the step put
/// there. A slot that held nothing has the step's own record removed — found by the slot and the
/// [owns] narrowing, which is deterministic because the step that is being undone maintains exactly
/// one record there. Tolerates a partial apply: a slot already back in its captured state is left
/// alone rather than failed on.
Future<void> restoreRecord(
  StepContext context, {
  required CloudflareAccess access,
  required CapturedRecord captured,
  bool Function(DnsRecord record)? owns,
}) async {
  final CloudflareToken token = await access.tokenFrom(context);
  if (token.refusal case final String refusal) {
    throw StateError(refusal);
  }
  if (captured.wasThere) {
    await writeRecord(
      context,
      access: access,
      token: token.value ?? '',
      zoneId: captured.zoneId,
      recordId: captured.id,
      body: recordBody(
        type: captured.type,
        name: captured.name,
        content: captured.content ?? '',
        proxied: captured.proxied,
      ),
    );
    return;
  }
  final RecordsReading reading = await recordsAt(
    context,
    access: access,
    token: token.value ?? '',
    zoneId: captured.zoneId,
    type: captured.type,
    fqdn: captured.name,
  );
  if (reading case RecordsUnreadable(:final String because)) {
    throw StateError(because);
  }
  final List<DnsRecord> records = <DnsRecord>[
    for (final DnsRecord record in (reading as RecordsHeld).records)
      if (owns == null || owns(record)) record,
  ];
  if (records.isEmpty) {
    // The slot is already the way it was captured: nothing stood there, nothing stands there.
    return;
  }
  if (records.length > 1) {
    throw StateError(
      '${records.length} ${captured.type} records stand at ${captured.name} where the step being '
      'undone maintained one — removing all of them could take away something this run never '
      'made, so nothing is touched',
    );
  }
  await removeRecord(
    context,
    access: access,
    token: token.value ?? '',
    zoneId: captured.zoneId,
    recordId: records.single.id,
  );
}

/// The answer [name] holds, or null where the run does not hold it or holds it empty.
///
/// Both cases come back as null on purpose: an empty domain or address composes a record about
/// nothing, and the caller's refusal for a missing answer is the right one for an empty one too.
String? answeredText(StepContext context, String name) {
  if (!context.answers.has(name)) {
    return null;
  }
  final String value = context.answers.text(name);
  return value.isEmpty ? null : value;
}

/// The refusal for an answer this run does not carry, naming [what] it would have been.
String missingAnswerRefusal(String name, String what) =>
    'this run holds no answer called "$name", and it is $what — without it there is nothing to '
    'publish';

/// What a record step decided after reading the zone, shared by its check, plan and apply.
///
/// One decision, computed one way, rendered three ways — the check answers it, the plan describes
/// it, the apply performs it. Computing it three times over would let the three drift, and the run
/// would then apply something its own plan never showed.
sealed class RecordDecision {
  const RecordDecision();
}

/// Something kept the zone from being read or the wish from being composed; nothing may be written.
final class RecordRefused extends RecordDecision {
  /// Records the refusal, [because].
  const RecordRefused(this.because);

  /// What stands in the way, in the words the check answers with.
  final String because;
}

/// The zone already holds what this step produces, so there is nothing to do.
final class RecordSettled extends RecordDecision {
  /// Records that the slot is already right, [because].
  const RecordSettled(this.because);

  /// What was found that shows the work is already done.
  final String because;
}

/// The zone does not hold it yet, and this is the write that gets it there.
final class RecordWrite extends RecordDecision {
  /// Records the write — a creation where [recordId] is null, a replacement otherwise.
  const RecordWrite({required this.zoneId, required this.body, this.recordId, this.before = ''});

  /// The zone the write goes into.
  final String zoneId;

  /// The record to replace, or null to create one.
  final String? recordId;

  /// What the slot holds now, empty where it holds nothing — for the plan's before/after line.
  final String before;

  /// The full body the write sends.
  final Map<String, Object?> body;

  /// The method the write uses, for the plan the operator reads.
  String get method => recordId == null ? 'POST' : 'PUT';
}
