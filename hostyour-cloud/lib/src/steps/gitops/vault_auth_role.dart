import 'package:ansiwise_api/ansiwise_api.dart';
import 'argument_text.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Writes one auth role as a single typed object.
///
/// A role is what turns an authenticated caller into a set of policies: which account, in which
/// namespace, holding which annotation, gets what. It is one object and it is written as one — a
/// field that is a map stays a map, and a field that is a list stays a list.
///
/// **The whole role goes in one body, and that is the fix for a real failure.** The shell this
/// replaces passed the role's fields as separate parameters through a shell inside a container, and
/// that shell collapsed a map field's escaped braces into a plain string. Vault answered that it
/// expected a map and got a string, on a role whose text looked right in the file. There is nothing
/// to collapse here.
///
/// **Writing a role replaces it whole, so a list field has to arrive complete.** Nothing about a
/// role write adds to what is there. A list recomputed from a program file alone therefore drops
/// every member something else put there — the namespace of every cluster onboarded after this file
/// was written — and their secret readers are then refused with "not authorized" and no line
/// naming why. [preserveList] is the field where that happened, read back from the live role and
/// unioned in before the write.
final class VaultAuthRole extends ReversibleStep {
  /// Writes the role [role] on auth mount [mount] of the Vault the profile in [repository] names.
  const VaultAuthRole({
    required this.repository,
    required this.mount,
    required this.role,
    required this.body,
    this.preserveList,
  });

  /// Builds the step from what the program gave it.
  factory VaultAuthRole.fromArguments(Arguments arguments) => VaultAuthRole(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    role: arguments.text('role'),
    body: arguments.text('body'),
    preserveList: arguments.optionalText('preserve_list'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile "
          "and the credential file Vault's root token was written to",
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes:
          'the auth mount this role lives on — "$kubernetesMountPlaceholder" for the mount this '
          "cluster's own workloads log in through, which the profile names",
    ),
    ArgumentSpec(
      name: 'role',
      kind: ArgumentKind.text,
      describes:
          'the role name, which the caller names when it logs in, and which may carry '
          '"$stagePlaceholder" where the callers of this platform expect the stage in it',
    ),
    ArgumentSpec(
      name: 'body',
      kind: ArgumentKind.text,
      describes:
          'the whole role as one JSON object, so a map field arrives as a map — its token_policies '
          'carry "$clusterPlaceholder" wherever they bind a policy of this cluster alone',
    ),
    ArgumentSpec(
      name: 'preserve_list',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'a list field whose members something else adds to, read back from the live role and '
          'unioned in so a re-run drops none of them',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = vaultAnswers;

  /// The checkout this installation runs from.
  final String repository;

  /// The auth mount.
  final String mount;

  /// The role name.
  final String role;

  /// The role, as one JSON object.
  final String body;

  /// The list field whose live members are kept, when there is one.
  final String? preserveList;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final _Role written = _writtenHere(context, vault);
    if (written.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';

    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Map<String, Object?>? declared = decodedObject(written.body);
    if (declared == null) {
      return CheckResult.blocked(
        'the role "${written.role}" is not written as a JSON object, and it is sent as one — a role '
        'whose map fields arrive as text is refused by Vault with a message about types rather than '
        'about this file',
      );
    }

    final String held = token.value ?? '';
    final Map<String, Object?>? current = await _current(context, url, held, written.path);
    if (current == null) {
      return const CheckResult.ready();
    }

    final Map<String, Object?> wanted = _merged(declared, current);
    for (final MapEntry<String, Object?> field in wanted.entries) {
      if (!sameJsonValue(current[field.key], field.value)) {
        context.log.debug('the role "${written.role}" differs from this run in ${field.key}');
        return const CheckResult.ready();
      }
    }
    return CheckResult.satisfied(
      'the role "${written.role}" on ${written.mount}/ is what this run writes',
    );
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final _Role written = _writtenHere(context, vault);
    if (written.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request('POST', '${vault.url}/v1/${written.path}', body: written.body);
  }

  @override
  Future<void> apply(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final _Role written = _writtenHere(context, vault);
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    final String held = token.value ?? '';
    final Map<String, Object?> declared = decodedObject(written.body) ?? const <String, Object?>{};
    final Map<String, Object?> wanted = _merged(
      declared,
      await _current(context, url, held, written.path) ?? const <String, Object?>{},
    );

    final HttpAnswer answer = await context.http.send(
      vaultWrite(url, written.path, token: held, body: wanted),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '$url/v1/${written.path}',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    final ClusterProfile vault = await clusterProfileFrom(context, repository);
    final _Role written = _writtenHere(context, vault);
    if (written.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.value case final String held) {
      await context.http.send(vaultDelete(vault.url ?? '', written.path, token: held));
    }
  }

  /// This role as this installation writes it, or why it cannot be written.
  ///
  /// All three at once, because the name, the mount and the body are one object to Vault and a
  /// refusal about any of them is the same refusal about this role.
  _Role _writtenHere(StepContext context, ClusterProfile profile) {
    final ArgumentText at = profile.forThisInstallation(context, mount);
    if (at.refusal case final String refusal) {
      return _Role.unwritable(refusal);
    }
    final ArgumentText named = profile.forThisInstallation(context, role);
    if (named.refusal case final String refusal) {
      return _Role.unwritable(refusal);
    }
    final ArgumentText object = profile.forThisInstallation(context, body);
    if (object.refusal case final String refusal) {
      return _Role.unwritable(refusal);
    }
    return _Role.written(mount: at.value ?? '', role: named.value ?? '', body: object.value ?? '');
  }

  /// The role Vault currently holds at [rolePath], or null when it holds none.
  Future<Map<String, Object?>?> _current(
    StepContext context,
    String url,
    String token,
    String rolePath,
  ) async {
    final HttpAnswer answer = await context.http.send(vaultRead(url, rolePath, token: token));
    return isAbsent(answer) ? null : decodedData(answer.body);
  }

  /// [declared] with [preserveList] widened by whatever the live role already holds there.
  Map<String, Object?> _merged(Map<String, Object?> declared, Map<String, Object?> current) {
    final String? field = preserveList;
    if (field == null) {
      return declared;
    }
    final Object? mine = declared[field];
    final Object? theirs = current[field];
    if (mine is! List<Object?> || theirs is! List<Object?>) {
      return declared;
    }
    final List<Object?> union = <Object?>[
      ...mine,
      for (final Object? member in theirs)
        if (!mine.contains(member)) member,
    ];
    return <String, Object?>{...declared, field: union};
  }
}

/// One role as this installation writes it, or why it cannot be written.
final class _Role {
  const _Role.written({required this.mount, required this.role, required this.body})
    : refusal = null;

  const _Role.unwritable(String this.refusal) : mount = '', role = '', body = '';

  final String mount;

  final String role;

  final String body;

  final String? refusal;

  /// Where this role lives, under Vault's version one API.
  String get path => 'auth/$mount/role/$role';
}
