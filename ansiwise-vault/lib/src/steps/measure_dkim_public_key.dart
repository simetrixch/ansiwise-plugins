import 'package:ansiwise_core/ansiwise_core.dart';

import 'argument_text.dart';
import 'vault_api.dart';
import 'vault_profile.dart';

/// Publishes the public half of the mail signing key pair the store holds, so the row that puts it
/// into the DNS is given exactly what the signer signs with.
///
/// **What cannot be written otherwise.** The record a receiver checks a signature against carries
/// the public half of the key the signer holds, and that key stands in one entry of the store,
/// written by the row that minted it where the store is seeded. A program that publishes the record
/// runs later, as its own act, and the one thing it may not do is carry the key as a value: a
/// program file ships to every installation and would carry one installation's key to all of them.
/// This step is the way across — it reads what the store holds and publishes it under a name a
/// later row takes.
///
/// **It READS the public half and derives nothing.** The entry carries the public half beside the
/// private one, written out of it by the row that minted the pair. Reading the private key here and
/// composing the public half a second time, with a rule of its own, would agree with the first only
/// by accident — and this step has no business reading a private key at all.
///
/// **An entry that holds no pair is a refusal, never an empty value.** A signing key nobody minted
/// is an installation that sends unsigned mail, and the row that takes this value has to know that
/// rather than be handed nothing: the sink refuses an empty text for exactly that reason. What the
/// refusal says is where the pair comes from, so the operator knows which run to make.
///
/// **It only reads.** Nothing on the machine changes, so a dry run performs it and the value is
/// there for the rows that follow.
final class MeasureDkimPublicKey extends ObservingStep {
  /// Publishes the field [publicKeyField] of the entry at [path] on [mount] of this installation's
  /// Vault.
  const MeasureDkimPublicKey({
    required this.repository,
    required this.mount,
    required this.path,
    required this.publicKeyField,
    required this.layout,
  });

  /// Builds the step from what the program gave it.
  factory MeasureDkimPublicKey.fromArguments(Arguments arguments) => MeasureDkimPublicKey(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    publicKeyField: arguments.text('public_key_field'),
    layout: VaultLayout.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile and "
          "the credential file Vault's root token was written to",
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
          'the entry, below the mount — it may carry the slot this row names under run_answer, '
          'where the entry belongs to one value of that axis rather than to all of them',
    ),
    ArgumentSpec(
      name: 'public_key_field',
      kind: ArgumentKind.text,
      describes:
          'the field of that entry the public half stands under, as the row that minted the pair '
          'wrote it — the one line of base64 a DKIM record\'s p= carries',
    ),
    ...VaultLayout.arguments,
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('dkim_public_key'),
      describes:
          'the public half of the mail signing key pair the entry holds, as the one line of base64 '
          "a DKIM record's p= carries",
    ),
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile and the credential file stand under the checkout.
  final VaultLayout layout;

  /// The key-value mount.
  final String mount;

  /// The entry below it.
  final String path;

  /// The field of the entry the public half stands under.
  final String publicKeyField;

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs
  /// in every mode, so a dry run holds the value the rows after this one read.
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
    final String dataPath = '$mount/data/${at.value ?? ''}';

    final HttpAnswer answer = await context.http.send(
      vaultRead(vault.url ?? '', dataPath, token: token.value ?? ''),
    );
    final VaultReading reading = readingOf(answer, path: dataPath);
    if (reading case final VaultUnreadable refused) {
      return CheckResult.blocked(refused.because);
    }
    final Object? held = reading is VaultHeld ? reading.data['data'] : null;
    final Object? publicKey = held is Map<String, Object?> ? held[publicKeyField] : null;
    if (publicKey is! String || publicKey.isEmpty) {
      return CheckResult.blocked(
        '$dataPath carries no $publicKeyField: the mail signing key pair is minted where this '
        'store is seeded, and an installation without it sends unsigned mail — seed the store '
        'before publishing a record for a key nothing signs with',
      );
    }
    context.measurements.publish(const MeasurementName('dkim_public_key'), publicKey);
    return CheckResult.satisfied('$dataPath holds the public half of the mail signing key');
  }
}
