/// Reaching Vault over its HTTP API, and reading the files one installation's secrets stand in.
///
/// **Why the API and not a command inside the pod.** The shell this replaces talked to Vault by
/// running the `vault` binary inside its server container through `kubectl exec`, and most of what
/// its comments are about follows from that one choice: `kubectl exec` arguments are visible in a
/// process listing to every process on the host, so the root token, the unseal keys and every other
/// credential all had to be fed on standard input instead, and a role body had to be sent as one
/// JSON object because the container's own shell collapsed backslash-escaped JSON into a string.
/// None of that exists here. A value travels in a request body or a request header, there is no
/// shell for it to become syntax in, and a map stays a map.
///
/// **The token rides `Authorization: Bearer` and not `X-Vault-Token`, and that is a decision about
/// the record.** Vault accepts either header. Only the first is a name the redactor removes on
/// sight, so the token cannot reach the record even on a run where nobody registered its value as a
/// secret.
library;

import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

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

/// The answers every step that talks to Vault reads, which is what their registry entries declare.
///
/// One name: the stage. It names the credential file and the hand-filled input, it is what the
/// `<stage>` slot stands for, and it is the only part of the connection an operator states — the
/// address itself is read out of the profile, never answered and never composed.
const List<String> vaultAnswers = <String>[vaultStageAnswer];

/// The name the stage is answered under, which is what names the credential file.
const String vaultStageAnswer = 'stage';

/// The text a configured path carries where the stage belongs — the name of the stage answer in
/// the angle brackets every marked slot of this family wears.
const String _stageSlot = '<$vaultStageAnswer>';

/// Where the quorum and the root token are, under the checkout at [repository].
///
/// The step's row says where ([credentials]), and this run's stage answer fills the stage's place
/// in it — the file is this installation's own, so no program file can write its name out whole.
String vaultCredentialsPath(
  StepContext context,
  String repository, {
  required String credentials,
}) => '$repository/${_stageFilled(context, credentials)}';

/// Where the one hand-filled input of this installation is, under the checkout at [repository].
String vaultSecretsPath(StepContext context, String repository, {required String secrets}) =>
    '$repository/${_stageFilled(context, secrets)}';

/// [text] with this run's stage in the place the slot marks.
String _stageFilled(StepContext context, String text) =>
    text.replaceAll(_stageSlot, context.answers.text(vaultStageAnswer));

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
bool isAbsent(HttpAnswer answer) => answer.status == 404;

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
  // Vault answers a number that was written as text as text, and the other way round, depending on
  // the field. Comparing the rendered form treats `"24h"` and `24` as themselves and everything
  // else structurally.
  return jsonEncode(a) == jsonEncode(b);
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
