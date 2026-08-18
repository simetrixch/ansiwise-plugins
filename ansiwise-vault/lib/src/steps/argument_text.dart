/// The names a program file cannot write down, and how they reach one step argument.
///
/// A program file ships inside the binary to every installation and nothing rewrites it, so no value
/// that belongs to ONE installation can stand in it. What stands there instead is a marked slot, and
/// the step fills it from the run: [clusterPlaceholder], [kubernetesMountPlaceholder] and
/// [vaultUrlPlaceholder] out of the profile the layout names, the layout's own `run_answer` slot out
/// of the answers, and [accessorPlaceholder] out of Vault itself.
///
/// **A slot is not a template, and this is the one marked-slot notation, not a second one.** A slot
/// is a lower-case name in angle brackets standing for exactly one value this run holds — no
/// expression, no condition and no loop. That distinction is what keeps the thing being debugged the
/// program rather than the configuration language, and it is the same shape [accessorPlaceholder]
/// has had since the first templated policy.
///
/// **All but one are known before the first request, and that one is not.** The accessor is
/// minted when an auth mount is enabled, so only the step that knows which mount an argument belongs
/// to can read it — that step reads it and hands it in here, rather than a second filling growing
/// beside this one.
///
/// **Anything still in angle brackets after filling is refused rather than sent.** The scan is
/// deliberately broader than the slot grammar: a misspelled or mis-cased name matches no declared
/// slot, so a scan that only knew the grammar would wave it through to Vault, where it would be
/// taken as part of a policy name, a mount path or a grant, be accepted there, and leave every
/// caller bound to it refused with a message about its own token.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

import 'vault_profile.dart';

/// The text a rules argument writes where the auth mount's accessor belongs.
///
/// A templated Vault policy interpolates `{{identity.entity.aliases.<accessor>.metadata...}}`, and
/// the accessor is minted when the mount is enabled — so it cannot be written into a program file.
/// The step reads it from Vault and hands it in.
const String accessorPlaceholder = '<accessor>';

/// The text a program file writes where this cluster's own short name belongs.
///
/// **The three slots filled out of the profile keep their spelling here, and that is a decision.**
/// What a vendor renames is the KEY the value is read from, and every one of those is a declared
/// argument with no default; the slot is only the notation this package offers for saying "the
/// value under that key goes here", the same for everybody who uses the package, like the accessor
/// slot above. What was per-product was the one slot standing for an answer of the RUN — a stage, a
/// region, whatever the product runs one tree per — and that name is the row's, not this file's.
///
/// **A policy name follows the profile's name key and never its auth-path key.** A deployment can
/// write the short name as a value of its own and the mount path as a composition over that same
/// name, so the two agree and either would produce the same policy name. Reading the short name
/// back out of the mount path spells one value through another: a mount path of any other shape
/// renames every policy under it while every role still binds the names it was given, and Vault
/// reports nothing — the callers bound to a policy that no longer exists are refused with a
/// message about their own tokens. The short name is also the wider fact. A policy is not scoped
/// to an auth mount at all: what the prefix separates is one cluster's policies from another's
/// inside one Vault.
const String clusterPlaceholder = '<cluster>';

/// The text a program file writes where the cluster's own auth mount belongs.
///
/// Read from the profile's auth-path key rather than composed out of the short name, because
/// whatever logs in through that mount reads that same key to decide where. A second composition
/// here would agree with what is deployed only by accident, and the disagreement shows up as a
/// login refused on a mount nobody wrote.
const String kubernetesMountPlaceholder = '<kubernetes-mount>';

/// The text a program file writes where the address of this installation's Vault belongs.
const String vaultUrlPlaceholder = '<vault-url>';

/// The text of one step argument once this installation's own names are in it, or why they are not.
final class ArgumentText {
  /// Records the text as it reaches Vault.
  const ArgumentText.of(String this.value) : refusal = null;

  /// Records that it cannot be written, because [refusal].
  const ArgumentText.unknown(String this.refusal) : value = null;

  /// The text, or null when there is none to be had.
  final String? value;

  /// Why there is none, or null when there is.
  final String? refusal;
}

/// Filling the marked slots of one step argument out of the run this profile was read on.
extension ArgumentPlaceholders on VaultProfile {
  /// [text] as it reaches Vault, with everything a program file cannot write filled in.
  ///
  /// [accessor] is the one value that comes from Vault rather than from the profile or the answers,
  /// so the step that knows which auth mount an argument templates on reads it and passes it. Left
  /// out where the text names no accessor — and where it names one and none was read, the refusal
  /// below is what says so.
  ArgumentText forThisInstallation(StepContext context, String text, {String? accessor}) {
    if (refusal case final String why) {
      return ArgumentText.unknown(why);
    }

    String written = layout.runAnswerFilled(context, text);
    if (written.contains(vaultUrlPlaceholder)) {
      written = written.replaceAll(vaultUrlPlaceholder, url ?? '');
    }
    if (written.contains(clusterPlaceholder)) {
      if (clusterName case final String name) {
        written = written.replaceAll(clusterPlaceholder, name);
      } else {
        return ArgumentText.unknown(_missing(path, layout.nameKey, clusterPlaceholder, text));
      }
    }
    if (written.contains(kubernetesMountPlaceholder)) {
      if (kubernetesAuthPath case final String mount) {
        written = written.replaceAll(kubernetesMountPlaceholder, mount);
      } else {
        return ArgumentText.unknown(
          _missing(path, layout.authPathKey, kubernetesMountPlaceholder, text),
        );
      }
    }
    if (accessor case final String minted) {
      written = written.replaceAll(accessorPlaceholder, minted);
    }

    if (_leftoverSlot.firstMatch(written)?.group(0) case final String left) {
      final String runSlot =
          layout.runSlot ?? 'no slot at all, because the row names no run_answer';
      return ArgumentText.unknown(
        '"$text" carries $left, and nothing in this run holds that name — a program file may write '
        '$vaultUrlPlaceholder, $clusterPlaceholder and $kubernetesMountPlaceholder, '
        '$accessorPlaceholder where the step reads an auth mount to fill it from, and for the '
        'answer this row names $runSlot; anything else would reach Vault as it stands',
      );
    }
    return ArgumentText.of(written);
  }
}

/// Anything at all between angle brackets, for the refusal that catches a name nothing filled —
/// including one the slot grammar would not accept, which is exactly what a misspelling looks like.
final RegExp _leftoverSlot = RegExp('<[^<>]*>');

/// Why [key] of the profile at [path] is needed and not there, for the slot [placeholder] in [text].
String _missing(String path, String key, String placeholder, String text) =>
    '$path does not carry $key, and $placeholder in "$text" stands for it — the deployment that '
    'generated this checkout writes that key into the profile, and nothing here composes the name '
    'in its place';
