import 'package:ansiwise_core/ansiwise_core.dart';

import 'vault_profile.dart';

/// Publishes the address this installation's Vault answers at, so a row that is not of this family
/// can be pointed at it.
///
/// **What cannot be written otherwise.** The address of one installation's Vault stands in the
/// profile, and the only notation a program file has for it is `<vault-url>` — a slot filled by
/// `ArgumentPlaceholders.forThisInstallation` out of that profile, which only a step carrying a
/// [VaultLayout] reads. So a wait, a probe or any other row that has to reach the same Vault has no
/// way to name where it is, and the one thing a program file may not do is write the address out:
/// a file ships to every installation and would carry one installation's address to all of them.
/// This step is the way across — it publishes what the family reads, under a name a later row
/// takes.
///
/// **It READS the address and composes nothing.** A second reading of the same key, with its own
/// rule for finding it, agrees with the first only by accident, and what that costs is exact: a
/// wait pointed one character away from the address the next row uses reports a Vault that is up
/// while the row after it cannot reach it. So the value published here is the one
/// [vaultProfileFrom] itself returned, and nothing is built out of the cluster's name or the host
/// it is served on.
///
/// **It only reads.** Nothing on the machine changes, so a dry run performs it and the value is
/// there for the rows that follow.
final class MeasureVaultUrl extends ObservingStep {
  /// Publishes the address the profile in [repository] records, at the place and under the key
  /// [layout] names.
  const MeasureVaultUrl({required this.repository, required this.layout});

  /// Builds the step from what the program gave it.
  factory MeasureVaultUrl.fromArguments(Arguments arguments) => MeasureVaultUrl(
    repository: arguments.text('repository'),
    layout: VaultLayout.fromArguments(arguments),
  );

  /// What this step accepts.
  ///
  /// The WHOLE layout list and not the one key this step reads. The family declares those names
  /// once so it cannot disagree about them, and a step picking a subset of them would be a second
  /// statement of the layout that drifts from the first the day a name changes.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile",
    ),
    ...VaultLayout.arguments,
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('vault_url'),
      describes: "the address this installation's Vault answers at, as its profile records it",
    ),
  ];

  /// The checkout this installation runs from.
  final String repository;

  /// Where the profile stands under the checkout, and under which key it carries the address.
  final VaultLayout layout;

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs
  /// in every mode, so a dry run holds the value the rows after this one read — and a step that
  /// only published while applying would leave a dry run planning against a measurement nobody
  /// made.
  @override
  Future<CheckResult> check(StepContext context) async {
    final VaultProfile vault = await vaultProfileFrom(context, repository, layout: layout);
    if (vault.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    // A profile that answered with no refusal carries an address: VaultProfile.read declares its
    // url as a required non-null field, and the reading has exactly those two outcomes. The `?? ''`
    // that the steps of this family write where they go on to FILL a slot would publish an empty
    // text here, which the sink refuses and which a later row could not tell from an address.
    final String url = vault.url!;
    context.measurements.publish(const MeasurementName('vault_url'), url);
    return CheckResult.satisfied("this installation's Vault answers at $url");
  }
}
