import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Takes one member out of one list field of one auth role, and touches nothing else of it.
///
/// **The shrinking half of `preserve_list`, and its own step for the same reason.** Naming a list
/// in a role write replaces that list whole, so the role step unions in whatever the live role
/// carries — which is exactly right for building and exactly wrong for removing: a member unioned
/// back in can never leave. This step reads the live role, drops the one member the row names, and
/// writes everything else back verbatim.
///
/// **A row that wants a whole list gone does not need this step.** Vault leaves a field the request
/// does not name exactly as it stands, so a list is emptied by NAMING it empty in the row that owns
/// the role — one statement in the declaration, where this step is a second writer beside it.
///
/// **A list that would become empty is refused, not written.** A role whose binding list names
/// nothing refuses every caller with a message about their own token — worse than the stale member,
/// because it takes the working callers down with the removed one. The refusal names the repair:
/// rewrite the role deliberately, with the step that owns its shape.
final class RemoveVaultRoleMember extends ReversibleStep<Map<String, Object?>?> {
  /// Removes [member] from the field [list] of the role [role] on auth mount [mount].
  const RemoveVaultRoleMember({
    required this.repository,
    required this.mount,
    required this.role,
    required this.list,
    required this.member,
    required this.layout,
  });

  /// Builds the step from what the program gave it.
  factory RemoveVaultRoleMember.fromArguments(Arguments arguments) => RemoveVaultRoleMember(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    role: arguments.text('role'),
    list: arguments.text('list'),
    member: arguments.text('member'),
    layout: VaultLayout.fromArguments(arguments),
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
          'the auth mount the role lives on — "$kubernetesMountPlaceholder" for the mount this '
          "cluster's own workloads log in through, which the profile names",
    ),
    ArgumentSpec(
      name: 'role',
      kind: ArgumentKind.text,
      describes: 'the role name, as the callers bound by it log in under',
    ),
    ArgumentSpec(
      name: 'list',
      kind: ArgumentKind.text,
      describes:
          'the list field the member is taken out of — the same field the writing rows name under '
          'preserve_list, because this is that mechanism\'s shrinking half',
    ),
    ArgumentSpec(
      name: 'member',
      kind: ArgumentKind.text,
      describes:
          'the one member to take out, spelled with the same slots the row that added it used — '
          'the sibling cluster the row names under cluster_answer fills its own slot',
    ),
    ...VaultLayout.arguments,
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The auth mount.
  final String mount;

  /// The role name.
  final String role;

  /// The list field the member is taken out of.
  final String list;

  /// The member, before its slots are filled.
  final String member;

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Read read = await _read(context);
    if (read.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Map<String, Object?>? held = read.role;
    if (held == null) {
      return CheckResult.satisfied(
        'the role "${read.roleName}" is not on ${read.mountPath}/ — it binds nobody, so there is '
        'no member to take out',
      );
    }
    final Object? members = held[list];
    if (members is! List<Object?> || !members.contains(read.memberValue)) {
      return CheckResult.satisfied(
        '$list of the role "${read.roleName}" does not carry "${read.memberValue}"',
      );
    }
    if (members.length == 1) {
      return CheckResult.blocked(
        '"${read.memberValue}" is the ONLY member of $list on the role "${read.roleName}", and a '
        'role whose binding list names nothing refuses every caller with a message about their own '
        'token — rewrite the role deliberately instead, with the step that owns its shape',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Read read = await _read(context);
    if (read.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${read.url}/v1/${read.rolePath}',
      body: 'the role as it stands, with "${read.memberValue}" taken out of $list',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final _Read read = await _read(context);
    if (read.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final Map<String, Object?>? held = read.role;
    if (held == null) {
      // Between the check and this moment somebody else removed the role — which leaves no member
      // bound, so there is nothing left to do.
      return;
    }
    final Object? members = held[list];
    if (members is! List<Object?> || !members.contains(read.memberValue)) {
      return;
    }
    final List<Object?> shrunk = <Object?>[
      for (final Object? one in members)
        if (one != read.memberValue) one,
    ];
    if (shrunk.isEmpty) {
      throw StateError(
        '"${read.memberValue}" is the ONLY member of $list on the role "${read.roleName}" — '
        'writing the role with an empty list would refuse every caller bound by it',
      );
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    final HttpAnswer answer = await context.http.send(
      vaultWrite(
        read.url,
        read.rolePath,
        token: token.value ?? '',
        body: <String, Object?>{...held, list: shrunk},
      ),
    );
    if (!answer.ok) {
      throw RequestRefused(
        method: 'POST',
        url: '${read.url}/v1/${read.rolePath}',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  /// The whole role as it stood, read before the shrink so an unwind can write it back verbatim.
  /// A role that was not there is captured as absence, and the undo then leaves absence alone.
  @override
  Future<Map<String, Object?>?> capture(StepContext context) async {
    final _Read read = await _read(context);
    if (read.refusal case final String refusal) {
      throw StateError(refusal);
    }
    return read.role;
  }

  @override
  Future<void> undo(StepContext context, Map<String, Object?>? captured) async {
    if (captured == null) {
      return;
    }
    final _Read read = await _read(context);
    if (read.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.value case final String held) {
      await context.http.send(vaultWrite(read.url, read.rolePath, token: held, body: captured));
    }
  }

  /// Everything one pass needs: the filled names, the address, and the role as Vault holds it —
  /// or the one refusal that stops the pass.
  Future<_Read> _read(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return _Read.unreadable(refusal);
    }
    final ArgumentText at = vault.forThisInstallation(context, mount);
    if (at.refusal case final String refusal) {
      return _Read.unreadable(refusal);
    }
    final ArgumentText named = vault.forThisInstallation(context, role);
    if (named.refusal case final String refusal) {
      return _Read.unreadable(refusal);
    }
    final ArgumentText one = vault.forThisInstallation(context, member);
    if (one.refusal case final String refusal) {
      return _Read.unreadable(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return _Read.unreadable(refusal);
    }

    final String url = vault.url ?? '';
    final String rolePath = 'auth/${at.value}/role/${named.value}';
    final HttpAnswer answer = await context.http.send(
      vaultRead(url, rolePath, token: token.value ?? ''),
    );
    return switch (readingOf(answer, path: rolePath)) {
      VaultHeld(:final Map<String, Object?> data) => _Read.of(
        url: url,
        mountPath: at.value ?? '',
        roleName: named.value ?? '',
        memberValue: one.value ?? '',
        rolePath: rolePath,
        role: data,
      ),
      VaultAbsent() => _Read.of(
        url: url,
        mountPath: at.value ?? '',
        roleName: named.value ?? '',
        memberValue: one.value ?? '',
        rolePath: rolePath,
        role: null,
      ),
      // Told apart from absence: a role nobody can read is not a role that binds nobody, and a
      // removal that read it that way would report done about a binding that still stands.
      VaultUnreadable(:final String because) => _Read.unreadable(because),
    };
  }
}

/// One pass over the inputs: the filled names and the live role, or the refusal that stops it.
final class _Read {
  const _Read.of({
    required this.url,
    required this.mountPath,
    required this.roleName,
    required this.memberValue,
    required this.rolePath,
    required this.role,
  }) : refusal = null;

  const _Read.unreadable(String this.refusal)
    : url = '',
      mountPath = '',
      roleName = '',
      memberValue = '',
      rolePath = '',
      role = null;

  /// Where Vault answers.
  final String url;

  /// The mount path, filled.
  final String mountPath;

  /// The role name, filled.
  final String roleName;

  /// The member, filled.
  final String memberValue;

  /// Where the role lives, under Vault's version one API.
  final String rolePath;

  /// The role as Vault holds it, or null when it holds none.
  final Map<String, Object?>? role;

  /// Why nothing can be read, or null when it can.
  final String? refusal;
}
