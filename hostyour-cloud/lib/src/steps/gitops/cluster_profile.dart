/// What the profile of this installation says, for the steps that talk to Vault.
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
///
/// **Where the file stands, and under which keys, is a program row's to say.** [VaultLayout]
/// carries those names as declared arguments, and their defaults are this platform's own layout —
/// the steps read a file either way, and a product that keeps the same facts somewhere else writes
/// its names into a row instead of forking the steps.
library;

import 'package:yaml/yaml.dart';

import 'package:ansiwise_api/ansiwise_api.dart';

import 'vault_api.dart';

/// Where the profile stands under the checkout, when a program names nowhere else.
const String vaultProfileDefault = 'cluster/profile.yaml';

/// The key the address is written under when a program names no other, spelled the way an operator
/// greps for it.
const String vaultUrlKey = 'global.vaultUrl';

/// The key this cluster's own short name is written under when a program names no other.
const String clusterNameKey = 'global.clusterName';

/// The key the cluster's own auth mount is written under when a program names no other.
const String kubernetesAuthPathKey = 'global.vaultKubernetesAuthPath';

/// Where one installation's profile and credential file stand, and under which keys the profile
/// carries its three values.
///
/// The five names are declared ONCE, in [arguments], and every step of the vault family spreads
/// that list into its own — so the family cannot disagree about a name or a default. What stands
/// UNDER the names is never an argument: the address is one installation's own, and the credential
/// file's content is minted, not configured.
final class VaultLayout {
  /// The layout a program row describes, which is this platform's own where it says nothing.
  const VaultLayout({
    this.profile = vaultProfileDefault,
    this.urlKey = vaultUrlKey,
    this.nameKey = clusterNameKey,
    this.authPathKey = kubernetesAuthPathKey,
    this.credentials = vaultCredentialsDefault,
  });

  /// Builds the layout from what the program gave the step carrying it.
  factory VaultLayout.fromArguments(Arguments arguments) => VaultLayout(
    profile: arguments.text('profile_path'),
    urlKey: arguments.text('vault_url_key'),
    nameKey: arguments.text('cluster_name_key'),
    authPathKey: arguments.text('kubernetes_auth_path_key'),
    credentials: arguments.text('credentials_path'),
  );

  /// The arguments every step of the vault family declares.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'profile_path',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: vaultProfileDefault,
      describes:
          'where the profile of this installation stands, under the checkout at repository — the '
          'file the step that stamps the cluster profile writes when the install branch is '
          'generated',
    ),
    ArgumentSpec(
      name: 'vault_url_key',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: vaultUrlKey,
      describes:
          'the key of the profile the address of Vault is written under. The address is read and '
          "never composed or answered: a slave points at the master's Vault, so no answer about "
          'this cluster could yield it',
    ),
    ArgumentSpec(
      name: 'cluster_name_key',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: clusterNameKey,
      describes:
          "the key of the profile this cluster's own short name is written under, which fills the "
          'slot that stands for it in a policy name',
    ),
    ArgumentSpec(
      name: 'kubernetes_auth_path_key',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: kubernetesAuthPathKey,
      describes:
          "the key of the profile the cluster's own auth mount is written under — read rather "
          'than composed, because the charts that render a secret store per namespace read the '
          'same key to decide where to log in',
    ),
    ArgumentSpec(
      name: 'credentials_path',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: vaultCredentialsDefault,
      describes:
          "where the quorum and Vault's root token are, under the checkout at repository — the "
          "stage answer fills the stage's place in it, so the file stands beside the other "
          'secrets of its stage',
    ),
  ];

  /// Where the profile stands, under the checkout.
  final String profile;

  /// The key of the profile the address of Vault is written under.
  final String urlKey;

  /// The key of the profile this cluster's own short name is written under.
  final String nameKey;

  /// The key of the profile the cluster's own auth mount is written under.
  final String authPathKey;

  /// Where the credential file stands, under the checkout, with the stage's place marked.
  final String credentials;
}

/// What the profile says about this installation, for the steps that talk to Vault.
///
/// A profile that cannot be read at all blocks every step rather than letting anything guess — a
/// guessed address reaches a Vault that answers, and answers wrongly, and nothing reports that until
/// a secret cannot be resolved. The two names are refused one at a time instead, where the argument
/// carrying the slot that stands for one is written, because most steps need neither.
final class ClusterProfile {
  /// Records the profile at [path] as it was read.
  const ClusterProfile.read({
    required this.path,
    required this.layout,
    required String this.url,
    this.clusterName,
    this.kubernetesAuthPath,
  }) : refusal = null;

  /// Records that the profile at [path] could not be read, because [refusal].
  const ClusterProfile.unknown({
    required this.path,
    required this.layout,
    required String this.refusal,
  }) : url = null,
       clusterName = null,
       kubernetesAuthPath = null;

  /// Where the profile stands, which is what a refusal names.
  final String path;

  /// The names this reading looked under.
  ///
  /// Carried with the answer and not left to whoever reports it. A refusal that named the key this
  /// package was COMPILED with rather than the one the run was told to look under would send an
  /// operator to add a key nothing will ever read — and it would read as true, because it was true
  /// before the names became a program row's to say.
  final VaultLayout layout;

  /// Where Vault answers, or null when the profile could not be read at all.
  final String? url;

  /// What this cluster is called among its siblings, or null where the profile carries no name.
  final String? clusterName;

  /// The auth mount every workload on this cluster logs in through, or null where it is not there.
  final String? kubernetesAuthPath;

  /// Why nothing can be read, or null when it can.
  final String? refusal;
}

/// Reads what the profile in [repository] says about this installation, at the place and under the
/// keys [layout] names.
Future<ClusterProfile> clusterProfileFrom(
  StepContext context,
  String repository, {
  VaultLayout layout = const VaultLayout(),
}) async {
  final String path = '$repository/${layout.profile}';
  if (!await context.files.exists(path)) {
    return ClusterProfile.unknown(
      layout: layout,
      path: path,
      refusal:
          '$path is not on this host, and its ${layout.urlKey} is the only place the address of '
          "this installation's Vault is written — the step that stamps the cluster profile writes "
          'it when the install branch is generated',
    );
  }

  final YamlNode profile;
  try {
    profile = loadYamlNode(await context.files.read(path));
  } on YamlException {
    return ClusterProfile.unknown(
      layout: layout,
      path: path,
      refusal:
          '$path cannot be parsed, and its ${layout.urlKey} is the only place the address of this '
          "installation's Vault is written — repair the file rather than typing the address "
          'anywhere',
    );
  }

  final String? url = _text(profile, layout.urlKey);
  if (url == null) {
    return ClusterProfile.unknown(
      layout: layout,
      path: path,
      refusal:
          '$path does not carry ${layout.urlKey}, and that key is where the address of this '
          "installation's Vault is written when the install branch is stamped — nothing here "
          'composes an address in its place, because a composed one would reach a Vault that '
          'answers and answers wrongly',
    );
  }
  return ClusterProfile.read(
    layout: layout,
    path: path,
    url: url,
    clusterName: _text(profile, layout.nameKey),
    kubernetesAuthPath: _text(profile, layout.authPathKey),
  );
}

/// The value [profile] carries under the dotted [key], or null where it carries none.
String? _text(YamlNode profile, String key) {
  YamlNode? at = profile;
  for (final String name in key.split('.')) {
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
