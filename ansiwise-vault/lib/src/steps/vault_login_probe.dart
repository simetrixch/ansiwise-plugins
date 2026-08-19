import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Proves that one kubernetes auth mount can validate a login end to end, with a real login
/// attempt.
///
/// **What is being proven is the mount's connection to its cluster, and nothing else can prove
/// it.** A mount that validates logins against ANOTHER cluster carries three values that must agree
/// exactly — the API address, the certificate authority and the reviewing credential — and a
/// mismatch in any of them has no error at write time: the mount accepts its configuration and then
/// refuses every login, hours later, as an opaque failure of whatever secret reader tried first.
/// The one act that exercises all three at once is a login, so this step performs one.
///
/// **The expected answer is a REFUSAL, and that is the design rather than a compromise.** The
/// credential this probe presents is the mount's own reviewing credential, whose account the row's
/// role deliberately does not bind. Vault can only refuse it BY THE ROLE'S BOUNDS after the whole
/// round trip has worked — the token review reached the cluster, the certificate matched, the token
/// was validated — so "not authorized" is the proof, and nothing is granted along the way. A login
/// that unexpectedly succeeds proves the same round trip and is reported as such.
///
/// **A probe is a measurement, so it lives in the check and runs in every mode.** The refused login
/// mints nothing and changes nothing on either side. What is told apart is the one failure with a
/// named repair: a review that reached the cluster and then could not READ there — the reviewing
/// account is missing its read grants — is reported as exactly that, because as a secret reader's
/// failure it says nothing about its cause.
final class VaultLoginProbe extends ObservingStep {
  /// Probes the mount at [mount] with the credential the answer [jwtAnswer] names.
  const VaultLoginProbe({
    required this.repository,
    required this.mount,
    required this.role,
    required this.jwtAnswer,
    required this.layout,
  });

  /// Builds the step from what the program gave it.
  factory VaultLoginProbe.fromArguments(Arguments arguments) => VaultLoginProbe(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    role: arguments.text('role'),
    jwtAnswer: arguments.text('jwt_answer'),
    layout: VaultLayout.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile",
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes:
          'the auth mount the login is attempted on — the mount an earlier row configured against '
          'the sibling cluster, spelled with the same slots that row used',
    ),
    ArgumentSpec(
      name: 'role',
      kind: ArgumentKind.text,
      describes:
          'the role the login names. Pick one whose bindings deliberately EXCLUDE the account '
          'behind the presented credential: the refusal by its bounds is what proves the round '
          'trip, and nothing is granted on the way',
    ),
    ArgumentSpec(
      name: 'jwt_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer that holds the credential the login presents — the reviewing '
          'credential the mount itself was configured with is the one at hand. It rides the '
          'request body and nowhere else',
    ),
    ...VaultLayout.arguments,
  ];

  /// The steps this rests on configure the mount this probes, so in the two modes that change
  /// nothing this step reports what it would prove rather than failing on a mount nobody made yet.
  @override
  bool get restsOnAnEarlierStep => true;

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile stands under the checkout.
  final VaultLayout layout;

  /// The auth mount, before its slots are filled.
  final String mount;

  /// The role the login names.
  final String role;

  /// The name of the answer that holds the credential the login presents.
  final String jwtAnswer;

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText at = vault.forThisInstallation(context, mount);
    if (at.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText named = vault.forThisInstallation(context, role);
    if (named.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? jwt = context.answers.optionalText(jwtAnswer);
    if (jwt == null || jwt.isEmpty) {
      return CheckResult.blocked(
        'this run holds no answer "$jwtAnswer", and the login this probe performs presents it',
      );
    }

    final String url = vault.url ?? '';
    final String path = 'auth/${at.value}/login';
    final HttpAnswer answer;
    try {
      // A LOGIN ATTEMPT IS THE MEASUREMENT, and the expected outcome — refusal by the role's
      // bounds — mints nothing and changes nothing on either side. It is marked as the read it is,
      // so the probe runs in every mode; the one unexpected outcome, a login the role's bindings
      // admit, mints a token that expires by its own lease and is reported below.
      answer = await context.http.send(
        HttpRequest(
          'POST',
          '$url/v1/$path',
          headers: const <String, String>{'content-type': 'application/json'},
          body: '{"role":"${named.value}","jwt":"${_jsonSafe(jwt)}"}',
          timeout: vaultTimeout,
          observes: true,
        ),
      );
    } on Object {
      return CheckResult.blocked(
        '$url/v1/$path could not be reached at all — the store itself is not answering, which says '
        'nothing about the mount this was going to prove',
      );
    }

    if (answer.ok) {
      return CheckResult.satisfied(
        'a login on $path went through — the mount reached its cluster and validated the '
        'credential. It was expected to be refused by the role\'s bounds, so check what the role '
        '"${named.value}" binds',
      );
    }

    final String errors = _errorsIn(answer.body);
    // ORDER MATTERS: the message that names the missing read grant ALSO says "not authorized", so
    // it is told apart first — it is the one failure with a repair of its own.
    if (errors.contains('failed to get namespace')) {
      return const CheckResult.blocked(
        'the mount reached its cluster and could not READ there: evaluating the role needs the '
        'namespace of the calling account, and the reviewing account on that cluster is missing '
        'its read grants — every real login will fail the same way until they are granted',
      );
    }
    if (errors.contains('not authorized')) {
      return CheckResult.satisfied(
        'the login on $path was refused by the role\'s bounds alone — an answer only a validated '
        'token can get, so the mount\'s address, certificate and reviewing credential all work',
      );
    }
    return CheckResult.blocked(
      'the login on $path failed in the wiring itself (status ${answer.status}: '
      '${errors.isEmpty ? 'no error text' : errors}) — the mount\'s address, certificate '
      'authority and reviewing credential are where to look',
    );
  }

  /// The `errors` list of a Vault answer, joined, or empty when there is none.
  static String _errorsIn(String body) {
    final Object? errors = decodedObject(body)?['errors'];
    if (errors is! List<Object?>) {
      return '';
    }
    return errors.whereType<String>().join('; ');
  }

  /// [value] with the two characters that would break out of a JSON string escaped.
  ///
  /// The credential is a token in an alphabet with neither, but never rely on that: a value that
  /// could break out of its string would become syntax in the request body.
  static String _jsonSafe(String value) => value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
