/// Reaching Vault over its HTTP API, and reading the files one installation's secrets stand in.
///
/// **Why the API and not a command inside the container.** The shell this replaces talked to Vault
/// by running the `vault` binary inside its server container, executed there from outside, and most
/// of what its comments are about follows from that one choice: the arguments of such a command are
/// visible in a process listing to every process on the machine, so the root token, the unseal keys
/// and every other credential all had to be fed on standard input instead, and a role body had to be
/// sent as one JSON object because the container's own shell collapsed backslash-escaped JSON into a
/// string. None of that exists here. A value travels in a request body or a request header, there is
/// no shell for it to become syntax in, and a map stays a map.
///
/// **The token rides `Authorization: Bearer` and not `X-Vault-Token`, and that is a decision about
/// the record.** Vault accepts either header. Only the first is a name the redactor removes on
/// sight, so the token cannot reach the record even on a run where nobody registered its value as a
/// secret.
library;

import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'vault_profile.dart';

/// How long any one call to Vault may take before the run gives up on it.
///
/// Explicit because the default is to wait forever, and a Vault that accepts the connection and then
/// hangs — a sealed one behind a proxy, an unfinished certificate — would otherwise turn one slow
/// dependency into a run nobody can tell from a working one.
const Duration vaultTimeout = Duration(seconds: 30);

/// The label the credential file carries the root token under.
///
/// The text is a contract rather than a formatting choice: it is the label Vault's own
/// `operator init` output prints, the file is read back by this program on every later run, and
/// whatever else a deployment points at the file parses the same label — changing it breaks every
/// reader at once with nothing naming the cause.
const String rootTokenLabel = 'Root Token';

/// The label the credential file carries each unseal key under, before its number.
const String unsealKeyLabel = 'Unseal Key';

/// The root token the credential file carries, or null when it carries none.
String? rootTokenIn(String credentials) => _labelled(credentials, '$rootTokenLabel:');

/// The root token a step was able to read, or why it could not.
///
/// Every step that writes to Vault needs the same three answers about the same file — is it there,
/// does it parse, does it carry a token — and each of the three is a refusal an operator acts on
/// differently. Returned as a value rather than thrown, so a step turns it into a blocked check
/// and the program's declared failure policy decides what that costs.
final class RootToken {
  /// Records that the token was read.
  const RootToken.read(this.value) : refusal = null;

  /// Records that it could not be read, because [refusal].
  const RootToken.unreadable(this.refusal) : value = null;

  /// The token, or null when there is none to be had.
  final String? value;

  /// Why there is none, or null when there is.
  final String? refusal;
}

/// Reads Vault's root token out of the credential file at [path].
Future<RootToken> rootTokenFrom(StepContext context, String path) async {
  final String? unfilled = unfilledSlotRefusal(path);
  if (unfilled != null) {
    return RootToken.unreadable(unfilled);
  }
  if (!await context.files.exists(path)) {
    return RootToken.unreadable(
      '$path is not on this host, and it is where Vault\'s root token is — the step that '
      'initializes Vault writes it and nothing else can produce it again',
    );
  }
  final String content = await context.files.read(path);
  final String? crlf = carriageReturnRefusal(path, content);
  if (crlf != null) {
    return RootToken.unreadable(crlf);
  }
  final String? token = rootTokenIn(content);
  return token == null
      ? RootToken.unreadable('$path carries no "$rootTokenLabel:" line')
      : RootToken.read(token);
}

/// Why [path] cannot be used as it stands, or null when it can.
///
/// A path still carrying angle brackets is a path whose slot nothing filled — the program named an
/// answer this run does not hold, or none at all while writing a slot anyway. Refused with the slot
/// still in it rather than sent to the file system: a file called `vault-<stage>.txt` does not
/// exist either way, and the refusal that says only "not on this host" would send an operator
/// looking for a file nobody ever meant to write.
String? unfilledSlotRefusal(String path) {
  final String? slot = _leftoverSlot.firstMatch(path)?.group(0);
  return slot == null
      ? null
      : '$path still carries $slot, and nothing in this run holds that name — the row that names '
            'the answer filling it is where that is decided, and the program has to declare an '
            'answer of that name for the operator to be asked for one';
}

/// Anything at all between angle brackets, which is what an unfilled slot looks like.
final RegExp _leftoverSlot = RegExp('<[^<>]*>');

/// Where the quorum and the root token are, under the checkout at [repository].
///
/// The step's row says where ([VaultLayout.credentials]), and this run's own value for the answer
/// the layout names fills the slot in it — the file is this installation's own, so no program file
/// can write its name out whole.
String vaultCredentialsPath(
  StepContext context,
  String repository, {
  required VaultLayout layout,
}) => '$repository/${layout.runAnswerFilled(context, layout.credentials)}';

/// Where the one hand-filled input of this installation is, under the checkout at [repository].
String vaultSecretsPath(
  StepContext context,
  String repository, {
  required String secrets,
  required VaultLayout layout,
}) => '$repository/${layout.runAnswerFilled(context, secrets)}';

/// Every unseal key the credential file carries, in the order the file writes them.
///
/// The keys are fed one at a time by the caller and the seal state is read again after each, so the
/// order here is only the order they are offered in — a rejected key does not consume the attempt
/// budget of the ones behind it.
List<String> unsealKeysIn(String credentials) => <String>[
  for (final String line in const LineSplitter().convert(credentials))
    if (line.trimLeft().startsWith(unsealKeyLabel))
      if (_afterColon(line) case final String key) key,
];

/// The whole text of the credential file, as every reader of it expects to find it.
///
/// The escrow sentence is part of the file and not only of the run output: the run that wrote it
/// scrolls away, and this file is then the only place that says it is the sole copy.
String renderCredentials({
  required String url,
  required List<String> unsealKeys,
  required String rootToken,
}) => <String>[
  'Vault: $url',
  for (int i = 0; i < unsealKeys.length; i++) '$unsealKeyLabel ${i + 1}: ${unsealKeys[i]}',
  '$rootTokenLabel: $rootToken',
  '',
  'COPY THIS FILE OFF THE HOST. Whatever unseals this Vault after a restart reads it from here, so',
  'it is also the only escrow left if this disk is lost. Re-initializing Vault is not a way to get',
  'another copy: it means destroying the storage and every secret in it.',
  '',
].join('\n');

/// Why [path] cannot be parsed, or null when it can.
///
/// A carriage return inside a credential is refused before the value is read rather than after,
/// because every symptom it produces names something else: a return inside the root token makes
/// every call answer 403, one inside an unseal key makes Vault reject that key on every attempt
/// forever, and one inside an OIDC client secret answers `invalid_client` at token exchange. None of
/// them says "this file came back from escrow through an editor that rewrote its line endings".
String? carriageReturnRefusal(String path, String content) => content.contains('\r')
    ? '$path carries a carriage return, and a credential read out of it would carry one too — '
          'rewrite the file with unix line endings before this runs again'
    : null;

/// The JSON object [body] holds, or null when it holds something else or nothing at all.
///
/// Total on purpose. An answer that did not parse is a fact a step decides on, and a step that threw
/// while reading one would report a parser failure where the finding is that Vault did not answer.
Map<String, Object?>? decodedObject(String body) {
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

/// The `data` object of a Vault answer, or null when there is none.
Map<String, Object?>? decodedData(String body) {
  final Object? data = decodedObject(body)?['data'];
  return data is Map<String, Object?> ? data : null;
}

/// A request that reads [path] under Vault's version one API at [url].
///
/// A `GET`, so the framework derives on its own that it changes nothing — which is what lets a dry
/// run send it and still be a dry run.
HttpRequest vaultRead(String url, String path, {String? token}) =>
    HttpRequest('GET', '$url/v1/$path', headers: _headers(token), timeout: vaultTimeout);

/// A request that writes [body] to [path] under Vault's version one API at [url].
HttpRequest vaultWrite(
  String url,
  String path, {
  required String token,
  required Map<String, Object?> body,
  String method = 'POST',
}) => HttpRequest(
  method,
  '$url/v1/$path',
  headers: <String, String>{..._headers(token), 'content-type': 'application/json'},
  body: jsonEncode(body),
  timeout: vaultTimeout,
);

/// A request that removes [path] under Vault's version one API at [url].
HttpRequest vaultDelete(String url, String path, {required String token}) =>
    HttpRequest('DELETE', '$url/v1/$path', headers: _headers(token), timeout: vaultTimeout);

/// Whether [answer] means the thing asked about is not there.
///
/// Vault answers 404 both for a path that holds nothing and for one that was never written, and a
/// step reads both the same way: there is work to do.
///
/// **Not enough on its own to decide what a step may write**, and that is what [readingOf] is for.
/// This says only that 404 means absent; it says nothing about the answers that are neither 404 nor
/// understandable, and a step that takes "not 404" for "here is what stands there" reads a failure
/// as an empty entry.
bool isAbsent(HttpAnswer answer) => answer.status == 404;

/// What one read of the store actually told us, which is one of THREE things and not two.
///
/// **The defect this exists to make unwritable.** A step asked whether something was there, got a
/// yes-or-no answer built on `status == 404`, and every other failure — a 403 while a policy is
/// being written, a 500, a gateway's own error page, a body of a shape nobody expected — fell to the
/// same side as "there is nothing there". What followed was a step doing the thing it does when
/// nothing is there: minting a credential over a live one, or rewriting a role as though it carried
/// nothing.
///
/// The third case is the one that was missing. "I could not read it" is not an answer about the
/// store's contents at all, and a step that treats it as one reports success for a run that
/// destroyed something.
sealed class VaultReading {
  const VaultReading();
}

/// Nothing is written at that path yet, and a step may create it.
final class VaultAbsent extends VaultReading {
  /// Says the path holds nothing.
  const VaultAbsent();
}

/// The store answered, and this is what it holds.
final class VaultHeld extends VaultReading {
  /// Holds [data], the decoded body of the answer.
  const VaultHeld(this.data);

  /// What stands at the path, as the store gave it.
  final Map<String, Object?> data;
}

/// The store answered something no step may act on.
final class VaultUnreadable extends VaultReading {
  /// Could not be understood, [because].
  const VaultUnreadable(this.because);

  /// What was wrong with the answer, in the words a refusal uses.
  final String because;
}

/// What [answer] says about [path], told apart into the three cases.
///
/// The body is decoded here rather than by each caller, because deciding that an answer is
/// UNDERSTANDABLE and deciding what it says are the same act: an answer whose body will not decode
/// is exactly the case that would otherwise pass for empty.
VaultReading readingOf(HttpAnswer answer, {required String path}) {
  if (isAbsent(answer)) {
    return const VaultAbsent();
  }
  if (answer.status < 200 || answer.status >= 300) {
    return VaultUnreadable(
      'reading $path answered ${answer.status}, which says neither what it holds nor that it holds '
      'nothing — and a step that read it as nothing would write over whatever is there',
    );
  }
  final Map<String, Object?>? decoded = decodedData(answer.body);
  if (decoded == null) {
    return VaultUnreadable(
      'reading $path answered ${answer.status} with a body this cannot make sense of, so what stands '
      'there is unknown — and a step that read it as nothing would write over whatever is there',
    );
  }
  return VaultHeld(decoded);
}

/// Whether [a] and [b] are the same value once a list's order is set aside.
///
/// Vault returns the members of a list field in an order of its own, so comparing the encoded text
/// would report a difference on every run and rewrite a role that is already right.
bool sameJsonValue(Object? a, Object? b) {
  if (a is List<Object?> && b is List<Object?>) {
    if (a.length != b.length) {
      return false;
    }
    final List<String> left = a.map(jsonEncode).toList()..sort();
    final List<String> right = b.map(jsonEncode).toList()..sort();
    return left.join(',') == right.join(',');
  }
  // A DURATION IS ONE VALUE WITH TWO SPELLINGS, AND VAULT ANSWERS IN THE OTHER ONE. A role written
  // with `"ttl":"24h"` comes back holding `86400`, so comparing the rendered form reports a
  // difference on every run — and because the step writes the role and then asks again, it never
  // converges: the same role is rewritten forever and reported as never right. Measured on a real
  // machine, where the role step stopped a run with Vault holding exactly the value the row had
  // just written.
  //
  // Only the mixed case is read this way, and deliberately so. Two texts stay two texts and two
  // numbers stay two numbers; it is a number against a text that can be one value written twice,
  // and only where the text is a duration Vault itself would have accepted.
  final int? left = _seconds(a);
  final int? right = _seconds(b);
  if (left != null && right != null && (a is num) != (b is num)) {
    return left == right;
  }
  return jsonEncode(a) == jsonEncode(b);
}

/// [value] as a whole number of seconds, or null where it is not a duration Vault would take.
///
/// Vault's own grammar: a bare number is seconds, and a text is a run of `<number><unit>` pieces
/// with `s`, `m`, `h` or `d` — `24h`, `1h30m`, `7d`. Anything else is not a duration and comes back
/// null, so a field whose value merely looks numeric is left to the ordinary comparison.
int? _seconds(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is! String || value.isEmpty) {
    return null;
  }
  const Map<String, int> units = <String, int>{'s': 1, 'm': 60, 'h': 3600, 'd': 86400};
  final Iterable<RegExpMatch> pieces = RegExp(r'(\d+)([smhd])').allMatches(value);
  if (pieces.isEmpty) {
    return null;
  }
  // Every character has to belong to a piece, or `24h and a bit` would read as twenty-four hours.
  if (pieces.map((RegExpMatch m) => m.group(0)!).join() != value) {
    return null;
  }
  int total = 0;
  for (final RegExpMatch piece in pieces) {
    total += int.parse(piece.group(1)!) * units[piece.group(2)!]!;
  }
  return total;
}

/// The values of [content] read as a file of `KEY=value` lines.
///
/// The hand-filled input of an installation is written this way, and it is read into an explicit
/// map here rather than sourced. A shell sourced it into its own process so that indirect expansion
/// could reach the variables a schema names; there is no such thing to reproduce, and a file that
/// can only be read by running it is a file that can run anything.
Map<String, String> shellAssignments(String content) {
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
/// An angle-bracketed name is how an example seed input says "fill this in", and no seeded value
/// can legitimately carry one: they are passwords, hex and base64 keys, certificates, bcrypt blobs,
/// JSON documents and tokens, and none of those alphabets has an angle bracket in it.
bool isUnfilled(String value) => value.contains('<') && value.contains('>');

Map<String, String> _headers(String? token) =>
    token == null ? const <String, String>{} : <String, String>{'authorization': 'Bearer $token'};

String? _labelled(String content, String label) {
  for (final String line in const LineSplitter().convert(content)) {
    if (line.trimLeft().startsWith(label)) {
      return _afterColon(line);
    }
  }
  return null;
}

String? _afterColon(String line) {
  final int colon = line.indexOf(':');
  if (colon < 0) {
    return null;
  }
  final String value = line.substring(colon + 1).trim();
  return value.isEmpty ? null : value;
}

String _unquoted(String value) {
  if (value.length >= 2) {
    final String first = value[0];
    if ((first == '"' || first == "'") && value.endsWith(first)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}
