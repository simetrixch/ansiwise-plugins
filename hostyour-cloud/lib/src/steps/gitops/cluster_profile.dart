/// What `cluster/profile.yaml` says about this installation, for the steps that talk to Vault.
///
/// Three values stand in that file and every one of them is READ rather than composed: where Vault
/// answers, what this cluster is called among its siblings, and the auth mount every workload on it
/// logs in through. The step that stamps the cluster profile writes all three when the install
/// branch is generated, and the charts that render a secret store per namespace read the same keys —
/// so a second composition here would agree with what is deployed only by accident, and the
/// disagreement shows up as a login refused on a mount nobody wrote.
///
/// **The address is the one relationship that crosses clusters.** A slave points at the master's
/// Vault, so no answer about THIS cluster could yield it. That is why it is read out of a file the
/// branch stamp wrote rather than answered by an operator or built out of the cluster's own name.
library;

import 'package:yaml/yaml.dart';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Where the profile carrying the address of Vault is, under the checkout at [repository].
String vaultProfilePath(String repository) => '$repository/cluster/profile.yaml';

/// The key of the profile the address is written under, spelled the way an operator greps for it.
const String vaultUrlKey = 'global.vaultUrl';

/// The key of the profile this cluster's own short name is written under.
const String clusterNameKey = 'global.clusterName';

/// The key of the profile the cluster's own auth mount is written under.
const String kubernetesAuthPathKey = 'global.vaultKubernetesAuthPath';

/// What `cluster/profile.yaml` says about this installation, for the steps that talk to Vault.
///
/// A profile that cannot be read at all blocks every step rather than letting anything guess — a
/// guessed address reaches a Vault that answers, and answers wrongly, and nothing reports that until
/// a secret cannot be resolved. The two names are refused one at a time instead, where the argument
/// carrying the slot that stands for one is written, because most steps need neither.
final class ClusterProfile {
  /// Records the profile at [path] as it was read.
  const ClusterProfile.read({
    required this.path,
    required String this.url,
    this.clusterName,
    this.kubernetesAuthPath,
  }) : refusal = null;

  /// Records that the profile at [path] could not be read, because [refusal].
  const ClusterProfile.unknown({required this.path, required String this.refusal})
    : url = null,
      clusterName = null,
      kubernetesAuthPath = null;

  /// Where the profile stands, which is what a refusal names.
  final String path;

  /// Where Vault answers, or null when the profile could not be read at all.
  final String? url;

  /// What this cluster is called among its siblings, or null where the profile carries no name.
  final String? clusterName;

  /// The auth mount every workload on this cluster logs in through, or null where it is not there.
  final String? kubernetesAuthPath;

  /// Why nothing can be read, or null when it can.
  final String? refusal;
}

/// Reads what the profile in [repository] says about this installation.
Future<ClusterProfile> clusterProfileFrom(StepContext context, String repository) async {
  final String path = vaultProfilePath(repository);
  if (!await context.files.exists(path)) {
    return ClusterProfile.unknown(
      path: path,
      refusal:
          '$path is not on this host, and its $vaultUrlKey is the only place the address of this '
          "installation's Vault is written — the step that stamps the cluster profile writes it "
          'when the install branch is generated',
    );
  }

  final YamlNode profile;
  try {
    profile = loadYamlNode(await context.files.read(path));
  } on YamlException {
    return ClusterProfile.unknown(
      path: path,
      refusal:
          '$path cannot be parsed, and its $vaultUrlKey is the only place the address of this '
          "installation's Vault is written — repair the file rather than typing the address "
          'anywhere',
    );
  }

  final String? url = _globalText(profile, 'vaultUrl');
  if (url == null) {
    return ClusterProfile.unknown(
      path: path,
      refusal:
          '$path does not carry $vaultUrlKey, and that key is where the address of this '
          "installation's Vault is written when the install branch is stamped — nothing here "
          'composes an address in its place, because a composed one would reach a Vault that '
          'answers and answers wrongly',
    );
  }
  return ClusterProfile.read(
    path: path,
    url: url,
    clusterName: _globalText(profile, 'clusterName'),
    kubernetesAuthPath: _globalText(profile, 'vaultKubernetesAuthPath'),
  );
}

/// The value [profile] carries under `global.[key]`, or null where it carries none.
String? _globalText(YamlNode profile, String key) {
  YamlNode? at = profile;
  for (final String name in <String>['global', key]) {
    if (at case final YamlMap map) {
      at = map.nodes[name];
      continue;
    }
    at = null;
    break;
  }
  if (at?.value case final String text when text.trim().isNotEmpty) {
    return text.trim();
  }
  return null;
}
