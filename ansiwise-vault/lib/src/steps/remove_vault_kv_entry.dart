import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Removes one key-value entry whole: every version and the metadata that held them.
///
/// **The metadata delete and not the soft one, on purpose.** A data delete leaves every version
/// standing and undeletable, so a later create-only write finds the slot occupied and refuses — and
/// what a removal promises is that the next arrival of the same name starts clean. Only the
/// metadata delete keeps that promise, and it is also what makes this step the irreversible kind:
/// past it there is no version history to go back to.
///
/// **Absence is proven and never assumed.** The check reads the entry's metadata and reports done
/// only where the store itself answers that nothing is there; an answer nobody can read blocks the
/// step instead of passing for absence.
final class RemoveVaultKvEntry extends IrreversibleStep {
  /// Removes the entry at [path] on [mount] of the Vault the profile in [repository] names.
  const RemoveVaultKvEntry({
    required this.repository,
    required this.mount,
    required this.path,
    required this.layout,
  });

  /// Builds the step from what the program gave it.
  factory RemoveVaultKvEntry.fromArguments(Arguments arguments) => RemoveVaultKvEntry(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
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
      describes: 'the key-value mount the entry stands on',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the entry, below the mount, spelled with the same slots the row that wrote it used — '
          'the run_answer and cluster_answer slots fill from this run, so a removal takes away '
          'exactly the entry an earlier run made',
    ),
    ...VaultLayout.arguments,
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The key-value mount.
  final String mount;

  /// The entry below it, before its slots are filled.
  final String path;

  @override
  String get irreversibleReason =>
      'the metadata delete destroys every version of the entry at once, and there is no undelete — '
      'what the versions held exists nowhere else afterwards';

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String metadataPath = _metadataPath(entry.value ?? '');
    final HttpAnswer answer = await context.http.send(
      vaultRead(vault.url ?? '', metadataPath, token: token.value ?? ''),
    );
    if (isAbsent(answer)) {
      return CheckResult.satisfied('the store holds nothing at $metadataPath');
    }
    if (!answer.ok) {
      return CheckResult.blocked(
        'reading $metadataPath answered ${answer.status}, which says neither what it holds nor '
        'that it holds nothing — and a removal acting on that would report done about an entry '
        'that may still be there',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'DELETE',
      '${vault.url}/v1/${_metadataPath(entry.value ?? '')}',
      body: 'every version of the entry and the metadata that held them',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText entry = vault.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    final String metadataPath = _metadataPath(entry.value ?? '');
    final HttpAnswer answer = await context.http.send(
      vaultDelete(url, metadataPath, token: token.value ?? ''),
    );
    if (!answer.ok && !isAbsent(answer)) {
      throw RequestRefused(
        method: 'DELETE',
        url: '$url/v1/$metadataPath',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  /// Where the entry [at] has its metadata, under Vault's version one API — the surface whose
  /// delete takes every version with it.
  String _metadataPath(String at) => '$mount/metadata/$at';
}
