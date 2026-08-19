import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Disables one auth mount, and with it every role it carried.
///
/// **The removal half of what the enable step warns about.** Disabling a mount destroys its
/// accessor and every login alias made through it, and a mount enabled again at the same path is a
/// NEW mount with a new accessor — every policy templated on the old one then resolves to nothing,
/// silently. That is exactly why this is its own step and never the enable step's undo path: it is
/// reached only where a program says, in its own row, that this mount's cluster is being taken away
/// for good.
///
/// **Guarded on the TYPE where the row states one.** A removal aims at the mount an earlier run
/// made, and a mount of another type standing at the same path is not that mount — deleting it
/// would take away something this program never created, on the strength of a name collision.
final class RemoveVaultAuthMethod extends IrreversibleStep {
  /// Disables the auth mount at [path] in the Vault the profile in [repository] names.
  const RemoveVaultAuthMethod({
    required this.repository,
    required this.path,
    required this.layout,
    this.type,
  });

  /// Builds the step from what the program gave it.
  factory RemoveVaultAuthMethod.fromArguments(Arguments arguments) => RemoveVaultAuthMethod(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    type: arguments.optionalText('type'),
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
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the mount path, spelled with the same slots the row that enabled it used — the sibling '
          'cluster the row names under cluster_answer fills its own slot, so a removal takes away '
          'exactly the mount an earlier run made for that cluster',
    ),
    ArgumentSpec(
      name: 'type',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the kind of auth method the mount is expected to be, as Vault names it. Stated, a mount '
          'of any other type at this path is refused rather than disabled — a name collision must '
          'not take away something this program never created',
    ),
    ...VaultLayout.arguments,
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The mount path, before its slots are filled.
  final String path;

  /// The kind of method the mount is expected to be, or null where the row states none.
  final String? type;

  @override
  String get irreversibleReason =>
      'disabling the mount destroys its accessor and every login alias made through it — a mount '
      'enabled again at the same path is a new mount with a new accessor, and every policy '
      'templated on the old one resolves to nothing';

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ArgumentText at = vault.forThisInstallation(context, path);
    if (at.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final _Mounted mounted = await _mountedType(
      context,
      vault.url ?? '',
      token.value ?? '',
      at.value ?? '',
    );
    if (mounted.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (mounted.type == null) {
      return CheckResult.satisfied('no auth mount stands at ${at.value}/');
    }
    if (type != null && mounted.type != type) {
      return CheckResult.blocked(
        '${at.value}/ is a ${mounted.type} auth mount and this removal is about a $type one — a '
        'name collision, and disabling it would take away something this program never created',
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
    final ArgumentText at = vault.forThisInstallation(context, path);
    if (at.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'DELETE',
      '${vault.url}/v1/sys/auth/${at.value}',
      body: 'the mount, its accessor, and every role and login alias it carried',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final ArgumentText at = vault.forThisInstallation(context, path);
    if (at.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String url = vault.url ?? '';
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    final HttpAnswer answer = await context.http.send(
      vaultDelete(url, 'sys/auth/${at.value}', token: token.value ?? ''),
    );
    if (!answer.ok && !isAbsent(answer)) {
      throw RequestRefused(
        method: 'DELETE',
        url: '$url/v1/sys/auth/${at.value}',
        status: answer.status,
        body: answer.body,
      );
    }
  }

  /// The type Vault at [url] holds at the mount path [at], its absence, or why neither is known.
  Future<_Mounted> _mountedType(StepContext context, String url, String token, String at) async {
    final HttpAnswer answer = await context.http.send(vaultRead(url, 'sys/auth', token: token));
    if (!answer.ok) {
      return _Mounted.unreadable(
        'listing the auth mounts answered ${answer.status}, which says neither that $at/ is there '
        'nor that it is not — and a removal acting on that would report done about a mount that '
        'may still be there',
      );
    }
    final Map<String, Object?>? mounts = decodedData(answer.body) ?? decodedObject(answer.body);
    if (mounts == null) {
      return _Mounted.unreadable(
        'the auth mount listing came back in a shape this cannot make sense of, so whether $at/ is '
        'there is unknown',
      );
    }
    final Object? mount = mounts['$at/'];
    final Object? held = mount is Map<String, Object?> ? mount['type'] : null;
    return held is String ? _Mounted.of(held) : const _Mounted.absent();
  }
}

/// What stands at one auth mount path: a type, absence, or why neither can be known.
final class _Mounted {
  const _Mounted.of(String this.type) : refusal = null;

  const _Mounted.absent() : type = null, refusal = null;

  const _Mounted.unreadable(String this.refusal) : type = null;

  /// The mount's type, or null when nothing stands there or the listing could not be read.
  final String? type;

  /// Why nothing can be known, or null when the listing was an answer.
  final String? refusal;
}
