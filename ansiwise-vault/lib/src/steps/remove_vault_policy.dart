import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Removes one named Vault policy.
///
/// **A policy left behind outlives the surface it scoped and reads as live.** Removing a cluster
/// from a shared Vault takes its mount and its roles away; a policy of that cluster that stays
/// behind is a grant document nothing binds today and anything named like the old roles binds
/// tomorrow — so a removal that leaves it is a removal that is not finished.
///
/// **Reversible, because the grants are readable until the delete.** What was there is captured
/// first and an unwind writes it back — a policy is its text and nothing else, which makes this the
/// rare removal that CAN be taken back. A policy already absent is captured as absent, and the undo
/// then leaves absence alone.
final class RemoveVaultPolicy extends ReversibleStep<String?> {
  /// Removes the policy [name] from the Vault the profile in [repository] names.
  const RemoveVaultPolicy({required this.repository, required this.name, required this.layout});

  /// Builds the step from what the program gave it.
  factory RemoveVaultPolicy.fromArguments(Arguments arguments) => RemoveVaultPolicy(
    repository: arguments.text('repository'),
    name: arguments.text('name'),
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
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'the policy name, spelled with the same slots the row that wrote it used — the sibling '
          'cluster the row names under cluster_answer fills its own slot, so a removal takes away '
          'exactly what an earlier run made for that cluster',
    ),
    ...VaultLayout.arguments,
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The policy name, before its slots are filled.
  final String name;

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText named = vault.forThisInstallation(context, name);
    if (named.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final _Held held = await _heldPolicy(
      context,
      vault.url ?? '',
      token.value ?? '',
      named.value ?? '',
    );
    if (held.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return held.text == null
        ? CheckResult.satisfied('Vault holds no policy "${named.value}"')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final ArgumentText named = vault.forThisInstallation(context, name);
    if (named.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'DELETE',
      '${vault.url}/v1/sys/policies/acl/${named.value}',
      body: 'the policy and every grant it carries',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText named = vault.forThisInstallation(context, name);
    if (named.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    final HttpAnswer answer = await context.http.send(
      vaultDelete(url, 'sys/policies/acl/${named.value}', token: token.value ?? ''),
    );
    if (!answer.ok && !isAbsent(answer)) {
      throw RequestRefused(
        method: 'DELETE',
        url: '$url/v1/sys/policies/acl/${named.value}',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  /// The policy text as it stood, read before the delete because afterwards nothing says what the
  /// grants were. The undo writes it back; a policy that was already absent is left absent.
  @override
  Future<String?> capture(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText named = vault.forThisInstallation(context, name);
    if (named.refusal != null) {
      return null;
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.value case final String held) {
      // A read that failed must not be captured as absence: an unwind would then leave a deleted
      // policy deleted while believing there had been nothing to put back.
      final _Held current = await _heldPolicy(context, vault.url ?? '', held, named.value ?? '');
      if (current.refusal case final String refusal) {
        throw StateError(refusal);
      }
      return current.text;
    }
    return null;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText named = vault.forThisInstallation(context, name);
    if (named.refusal != null) {
      return;
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.value case final String held) {
      await context.http.send(
        vaultWrite(
          vault.url ?? '',
          'sys/policies/acl/${named.value}',
          token: held,
          body: <String, Object?>{'policy': captured},
          method: 'PUT',
        ),
      );
    }
  }

  /// What Vault at [url] holds under [policy]: its text, absence, or why neither can be known.
  Future<_Held> _heldPolicy(StepContext context, String url, String token, String policy) async {
    final HttpAnswer answer = await context.http.send(
      vaultRead(url, 'sys/policies/acl/$policy', token: token),
    );
    if (isAbsent(answer)) {
      return const _Held.absent();
    }
    if (!answer.ok) {
      return _Held.unreadable(
        'reading the policy "$policy" answered ${answer.status}, which says neither what it holds '
        'nor that it holds nothing — and a removal acting on that would report done about a policy '
        'that may still be there',
      );
    }
    final Object? held = decodedData(answer.body)?['policy'];
    return held is String ? _Held.text(held) : const _Held.absent();
  }
}

/// One policy as Vault holds it, its absence, or why neither can be known.
final class _Held {
  const _Held.text(String this.text) : refusal = null;

  const _Held.absent() : text = null, refusal = null;

  const _Held.unreadable(String this.refusal) : text = null;

  /// The policy text, or null when Vault holds none or the answer could not be read.
  final String? text;

  /// Why nothing can be known, or null when the answer was an answer.
  final String? refusal;
}
