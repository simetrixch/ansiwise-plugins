/// The names a program file cannot write down, and how they reach one step argument.
///
/// A program file ships inside the binary to every installation and nothing rewrites it, so no value
/// that belongs to ONE installation can stand in it. What stands there instead is a marked slot, and
/// the step fills it from the run: [clusterPlaceholder], [kubernetesMountPlaceholder] and
/// [vaultUrlPlaceholder] out of `cluster/profile.yaml`, [stagePlaceholder] out of the answers, and
/// [accessorPlaceholder] out of Vault itself.
///
/// **A slot is not a template.** No expression, no condition and no loop, only a name standing for
/// one value this run holds. That distinction is what keeps the thing being debugged the program
/// rather than the configuration language, and it is the same shape [accessorPlaceholder] has had
/// since the first templated policy.
///
/// **Four of the five are known before the first request and the fifth is not.** The accessor is
/// minted when an auth mount is enabled, so only the step that knows which mount an argument belongs
/// to can read it — that step reads it and hands it in here, rather than a second filling growing
/// beside this one.
///
/// **Anything still in angle brackets after filling is refused rather than sent.** A misspelled slot
/// would otherwise reach Vault as part of a policy name, a mount path or a grant, be accepted there,
/// and leave every caller bound to it refused with a message about its own token.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

import '../slots.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// The text a rules argument writes where the auth mount's accessor belongs.
///
/// A templated Vault policy interpolates `{{identity.entity.aliases.<accessor>.metadata...}}`, and
/// the accessor is minted when the mount is enabled — so it cannot be written into a program file.
/// The step reads it from Vault and hands it in.
const String accessorPlaceholder = '<accessor>';

/// The text a program file writes where this cluster's own short name belongs.
///
/// **A policy name follows [clusterNameKey] and never [kubernetesAuthPathKey].** The profile writes
/// the short name as a value of its own and the mount path as `kubernetes-` in front of that same
/// name, so the two agree and either would produce the same policy name today. Reading the short
/// name back out of the mount path spells one value through another: a mount path of any other
/// shape renames every policy under it while every role still binds the names it was given, and
/// Vault reports nothing — the callers bound to a policy that no longer exists are refused with a
/// message about their own tokens. The short name is also the wider fact. A policy is not scoped to
/// an auth mount at all: `admin` is bound from the browser mount and `controller` from the cluster
/// mount, and what the prefix separates is one cluster's policies from another's inside one Vault.
const String clusterPlaceholder = '<cluster>';

/// The text a program file writes where the cluster's own auth mount belongs.
///
/// Read from [kubernetesAuthPathKey] rather than composed out of the short name, because the charts
/// that render a secret store per namespace read that same key to decide where to log in. A second
/// composition here would agree with what is deployed only by accident, and the disagreement shows
/// up as a login refused on a mount nobody wrote.
const String kubernetesMountPlaceholder = '<kubernetes-mount>';

/// The text a program file writes where the stage of this installation belongs.
///
/// Derived from the name the stage is answered under, so the slot and the answer cannot come apart.
const String stagePlaceholder = '<$vaultStageAnswer>';

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
extension ArgumentPlaceholders on ClusterProfile {
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

    String written = text;
    if (written.contains(stagePlaceholder)) {
      written = written.replaceAll(stagePlaceholder, context.answers.text(vaultStageAnswer));
    }
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

    if (leftoverSlotIn(written) case final String left) {
      return ArgumentText.unknown(
        '"$text" carries $left, and nothing in this run holds that name — a program file may write '
        '$stagePlaceholder, $vaultUrlPlaceholder, $clusterPlaceholder and '
        '$kubernetesMountPlaceholder, and $accessorPlaceholder where the step reads an auth mount '
        'to fill it from; anything else would reach Vault as it stands',
      );
    }
    return ArgumentText.of(written);
  }
}

/// Why [key] of the profile at [path] is needed and not there, for the slot [placeholder] in [text].
String _missing(String path, String key, String placeholder, String text) =>
    '$path does not carry $key, and $placeholder in "$text" stands for it — the step that stamps '
    'the cluster profile writes that key when the install branch is generated, and nothing here '
    'composes the name in its place';
