/// The profile: the file one installation declares its Vault facts in, for the steps that talk to
/// Vault.
///
/// Three values stand in that file and every one of them is READ rather than composed: where Vault
/// answers, the short name that tells this cluster's policies apart from another's inside a shared
/// Vault, and the kubernetes auth mount every workload on it logs in through. The deployment that
/// generated the checkout writes all three, and whatever else consumes them — a chart rendering a
/// secret store per namespace, a login redirect — reads the same keys. A second composition here
/// would agree with what is deployed only by accident, and the disagreement shows up as a login
/// refused on a mount nobody wrote.
///
/// **The address is the one relationship that can cross clusters.** A secondary cluster can point
/// at a primary's Vault, so no answer about THIS cluster could yield it. That is why it is read out
/// of a file the deployment wrote rather than answered by an operator or built out of the cluster's
/// own name.
///
/// **Where the file stands, and under which keys, is a program row's to say — always.** [VaultLayout]
/// carries those names as declared arguments and none of them has a default: this package knows the
/// tool and not any one product's file layout, so the layout is absent-or-stated, never guessed.
library;

import 'package:yaml/yaml.dart';

import 'package:ansiwise_core/ansiwise_core.dart';

/// Where one installation's profile and credential file stand, and under which keys the profile
/// carries its three values.
///
/// The names are declared ONCE, in [arguments], and every step of the vault family spreads that
/// list into its own — so the family cannot disagree about a name. What stands UNDER the
/// names is never an argument: the address is one installation's own, and the credential file's
/// content is minted, not configured.
final class VaultLayout {
  /// The layout exactly as a program row describes it.
  const VaultLayout({
    required this.profile,
    required this.urlKey,
    required this.nameKey,
    required this.authPathKey,
    required this.credentials,
    this.runAnswer,
    this.clusterAnswer,
  });

  /// Builds the layout from what the program gave the step carrying it.
  factory VaultLayout.fromArguments(Arguments arguments) => VaultLayout(
    profile: arguments.text('profile_path'),
    urlKey: arguments.text('vault_url_key'),
    nameKey: arguments.text('cluster_name_key'),
    authPathKey: arguments.text('kubernetes_auth_path_key'),
    credentials: arguments.text('credentials_path'),
    runAnswer: arguments.optionalText('run_answer'),
    clusterAnswer: arguments.optionalText('cluster_answer'),
  );

  /// The arguments every step of the vault family declares.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'profile_path',
      kind: ArgumentKind.text,
      describes:
          'where the profile of this installation stands, under the checkout at repository — the '
          'file the deployment writes its Vault address and cluster names into',
    ),
    ArgumentSpec(
      name: 'vault_url_key',
      kind: ArgumentKind.text,
      describes:
          'the key of the profile the address of Vault is written under. The address is read and '
          "never composed or answered: a cluster can point at another cluster's Vault, so no "
          'answer about this cluster could yield it',
    ),
    ArgumentSpec(
      name: 'cluster_name_key',
      kind: ArgumentKind.text,
      describes:
          "the key of the profile this cluster's own short name is written under, which fills the "
          'slot that stands for it in a policy name',
    ),
    ArgumentSpec(
      name: 'kubernetes_auth_path_key',
      kind: ArgumentKind.text,
      describes:
          "the key of the profile the cluster's own auth mount is written under — read rather "
          'than composed, because whatever logs in through that mount reads the same key to '
          'decide where',
    ),
    ArgumentSpec(
      name: 'credentials_path',
      kind: ArgumentKind.text,
      describes:
          "where the quorum and Vault's root token are, under the checkout at repository — it may "
          'carry the run_answer slot, and this run\'s value for it fills that place',
    ),
    // The ONE axis a product may run the same Vault layout along more than once, and the reason it
    // is named rather than known: Vault has no such axis. A product with three environments wants
    // one credential file and one tree of paths per environment, one with three regions wants the
    // same per region, and a product with neither wants none at all — so what the axis is CALLED is
    // the product's, and a name written into this package would make every vendor carry that one.
    //
    // Absent is a first-class case and not a mistake: with nothing here, no path and no rule is
    // filled from an answer, and a text still carrying angle brackets is refused rather than sent.
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name — write '
          '"stage" here and every "<stage>" in a path, a role or a policy rule of this family is '
          "filled with this run's stage. Leave it off where the product has no such axis",
      required: false,
    ),
    // The SECOND cluster one Vault can serve, and the reason it is an answer and not the profile's:
    // one secret store can serve several clusters, and the profile can only describe the cluster it
    // stands on. A run that builds or removes a SIBLING cluster's surface — its auth mount, its
    // policies, the entries written for it — has to be told which sibling, and the profile's own
    // short name (the <cluster> slot) keeps meaning the cluster this run stands on.
    //
    // Absent is a first-class case: with nothing here, no sibling slot is filled, and a text still
    // carrying angle brackets is refused rather than sent.
    ArgumentSpec(
      name: 'cluster_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer that holds the short name of the sibling cluster these rows act '
          'on, where one Vault serves several clusters — its value fills the slot spelled with '
          'that same name, beside the run_answer slot. Leave it off for rows about the cluster the '
          'profile itself describes',
      required: false,
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

  /// Where the credential file stands, under the checkout, with the run answer's place marked.
  final String credentials;

  /// The name of the answer whose value fills the slot spelled with that same name, or null where
  /// the product running these steps has no such axis.
  final String? runAnswer;

  /// The name of the answer holding the sibling cluster's short name, or null where these rows are
  /// about the cluster the profile itself describes.
  final String? clusterAnswer;

  /// The text that stands where this run's own value for [runAnswer] belongs, or null where there
  /// is no such answer.
  ///
  /// Derived from the name rather than declared beside it, so the slot and the answer cannot come
  /// apart: a program that renames the answer renames the slot in the same act.
  String? get runSlot => runAnswer == null ? null : '<$runAnswer>';

  /// The two answers whose values fill the slot spelled with their own name, in the order they are
  /// filled. A null entry is a layout that does not name that one.
  List<String?> get _fillingAnswers => <String?>[runAnswer, clusterAnswer];

  /// [text] with this run's own value for [runAnswer] and [clusterAnswer] where their slots mark
  /// it.
  ///
  /// Text carrying no slot, a layout naming no answer, and a run that does not hold the answer all
  /// come back unchanged — the last of them so the slot is still visible in whatever refusal
  /// reports the text, rather than being replaced by an empty string nobody could see.
  String runAnswerFilled(StepContext context, String text) {
    String written = text;
    for (final String? answer in _fillingAnswers) {
      if (answer == null || !context.answers.has(answer)) {
        continue;
      }
      final String slot = '<$answer>';
      if (written.contains(slot)) {
        written = written.replaceAll(slot, context.answers.text(answer));
      }
    }
    return written;
  }
}

/// What the profile says about this installation, for the steps that talk to Vault.
///
/// A profile that cannot be read at all blocks every step rather than letting anything guess — a
/// guessed address reaches a Vault that answers, and answers wrongly, and nothing reports that until
/// a secret cannot be resolved. The two names are refused one at a time instead, where the argument
/// carrying the slot that stands for one is written, because most steps need neither.
final class VaultProfile {
  /// Records the profile at [path] as it was read.
  const VaultProfile.read({
    required this.path,
    required this.layout,
    required String this.url,
    this.clusterName,
    this.kubernetesAuthPath,
  }) : refusal = null;

  /// Records that the profile at [path] could not be read, because [refusal].
  const VaultProfile.unknown({
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
  /// Carried with the answer and not left to whoever reports it. A refusal that named any key other
  /// than the one the run was told to look under would send an operator to add a key nothing will
  /// ever read.
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
Future<VaultProfile> vaultProfileFrom(
  StepContext context,
  String repository, {
  required VaultLayout layout,
}) async {
  final String path = '$repository/${layout.profile}';
  if (!await context.files.exists(path)) {
    return VaultProfile.unknown(
      layout: layout,
      path: path,
      refusal:
          '$path is not on this host, and its ${layout.urlKey} is the only place the address of '
          "this installation's Vault is written — the deployment that generated this checkout "
          'writes it there',
    );
  }

  final YamlNode profile;
  try {
    profile = loadYamlNode(await context.files.read(path));
  } on YamlException {
    return VaultProfile.unknown(
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
    return VaultProfile.unknown(
      layout: layout,
      path: path,
      refusal:
          '$path does not carry ${layout.urlKey}, and that key is where the address of this '
          "installation's Vault is written when the checkout is generated — nothing here composes "
          'an address in its place, because a composed one would reach a Vault that answers and '
          'answers wrongly',
    );
  }
  return VaultProfile.read(
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
