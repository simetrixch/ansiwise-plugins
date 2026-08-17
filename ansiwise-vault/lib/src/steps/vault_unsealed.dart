import 'package:ansiwise_api/ansiwise_api.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Feeds the quorum back until Vault serves.
///
/// A Vault that runs with the seal it was given a quorum for, and no key service behind it, comes
/// back sealed from every restart — a node reboot, an eviction, the roll a chart bump triggers.
/// While it is sealed nothing that reads from it materializes a secret, so this is not a bring-up
/// step that happens once: it is the step that converges the state a deployment stalls in.
///
/// **The keys are fed one at a time and the seal state is read again after each.** Feeding a fixed
/// number blind spends keys that were not needed and hides which one was rejected; asking after each
/// stops the moment the threshold is met, and a single rejected key does not consume the attempt
/// budget of the ones behind it.
///
/// **An already-unsealed Vault is nothing to do.** That is what makes this safe to put in the middle
/// of a program that also runs on a cluster which has been up for months.
final class VaultUnsealed extends ReversibleStep<bool?> {
  /// Unseals the Vault the profile in [repository] names, with the quorum of this stage.
  const VaultUnsealed({required this.repository, required this.layout, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory VaultUnsealed.fromArguments(Arguments arguments) => VaultUnsealed(
    repository: arguments.text('repository'),
    layout: VaultLayout.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile "
          'and the credential file the quorum was written to',
    ),
    ...VaultLayout.arguments,
    elevationArgument,
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// None by name. What this step reads out of the run is whichever answer the row's `run_answer`
  /// names, and that is a value of a program rather than of this package — so there is no name here
  /// that a resolver could hold a program to, and an answer the run does not carry leaves the slot
  /// standing and is refused by name where the text is used.
  static const List<String> answers = <String>[];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String url = vault.url ?? '';

    final String? refusal = await _quorumRefusal(context);
    if (refusal != null) {
      return CheckResult.blocked(refusal);
    }

    final bool? sealed = await _sealed(context, url);
    if (sealed == null) {
      return CheckResult.blocked(
        'Vault at $url answered nothing that says whether it is sealed, so whether anything can '
        'read a secret right now is unknown — which is not the same as it being fine',
      );
    }
    return sealed ? const CheckResult.ready() : CheckResult.satisfied('Vault at $url is unsealed');
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.request(
      'POST',
      '${vault.url}/v1/sys/unseal',
      body:
          'one key at a time out of ${vaultCredentialsPath(context, repository, layout: layout)}, until Vault '
          'reports itself unsealed',
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    final String url = vault.url ?? '';
    final String credentialsPath = vaultCredentialsPath(context, repository, layout: layout);
    final List<String> keys = unsealKeysIn(
      await context.files.read(credentialsPath, elevated: elevated),
    );

    for (int i = 0; i < keys.length; i++) {
      final HttpAnswer answer = await context.http.send(
        vaultWrite(
          url,
          'sys/unseal',
          // Unsealing is what a Vault does before it can authenticate anybody, so this call carries
          // no token — and the key travels in the body, where no process listing reaches it.
          token: '',
          body: <String, Object?>{'key': keys[i]},
        ),
      );

      final Object? sealed = decodedObject(answer.body)?['sealed'];
      if (sealed == false) {
        context.log.info('Vault is unsealed after ${i + 1} of ${keys.length} keys');
        return;
      }
      if (!answer.ok) {
        // Which key Vault refused and why, without the key. A rejected key that says nothing is the
        // shape a retrying unsealer once failed in on every attempt for days: the cause was a
        // carriage return inside every key and no line anywhere named it.
        context.log.warn(
          'Vault refused key ${i + 1} of ${keys.length} with ${answer.status} and stayed sealed',
        );
      }
    }

    // No throw. Whether Vault is unsealed is decided by asking Vault, which is what the check does
    // straight after this — a step that reported its own success here would be trusting the last
    // answer it happened to get.
    context.log.error('every key in $credentialsPath was offered and Vault is still sealed');
  }

  /// Whether Vault said it was sealed before this ran, or null when it said nothing that answers
  /// that.
  ///
  /// Read before the first key is offered, because sealing is what the undo does and a sealed Vault
  /// is one nothing materializes a secret from. Only a Vault this run found sealed is sealed
  /// again; one that was already serving, and one whose answer did not say, are left as they are.
  ///
  /// The quorum itself is not captured. It is read out of the credential file each time it is
  /// needed, and it is a credential — nothing carries it beyond the request that feeds it.
  @override
  Future<bool?> capture(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal != null) {
      return null;
    }
    return _sealed(context, vault.url ?? '');
  }

  @override
  Future<void> undo(StepContext context, bool? captured) async {
    if (captured != true) {
      return;
    }
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal != null) {
      return;
    }
    final String? token = rootTokenIn(
      await context.files.read(
        vaultCredentialsPath(context, repository, layout: layout),
        elevated: elevated,
      ),
    );
    if (token == null) {
      return;
    }
    await context.http.send(
      vaultWrite(vault.url ?? '', 'sys/seal', token: token, body: const <String, Object?>{}),
    );
  }

  /// Why the quorum cannot be fed back, or null when it can.
  Future<String?> _quorumRefusal(StepContext context) async {
    final String credentialsPath = vaultCredentialsPath(context, repository, layout: layout);
    if (!await context.files.exists(credentialsPath, elevated: elevated)) {
      return '$credentialsPath is not on this host, and it is the only place the unseal keys are — '
          'without it nothing on this machine can bring Vault back after a restart';
    }
    final String content = await context.files.read(credentialsPath, elevated: elevated);
    final String? crlf = carriageReturnRefusal(credentialsPath, content);
    if (crlf != null) {
      return crlf;
    }
    return unsealKeysIn(content).isEmpty
        ? '$credentialsPath carries no "$unsealKeyLabel <n>:" line, so there is no key in it to feed'
        : null;
  }

  /// Whether Vault says it is sealed, or null when it said nothing that answers that.
  Future<bool?> _sealed(StepContext context, String url) async {
    final HttpAnswer answer = await context.http.send(vaultRead(url, 'sys/seal-status'));
    final Object? sealed = decodedObject(answer.body)?['sealed'];
    return sealed is bool ? sealed : null;
  }
}
