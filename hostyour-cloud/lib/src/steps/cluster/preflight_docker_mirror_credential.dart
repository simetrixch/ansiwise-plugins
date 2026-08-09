import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Decides, before anything is installed, whether this machine can pull images through the mirror.
///
/// **Why it is here and not where the mirror is written.** The mirror is written part way through
/// the install, and a credential that is merely unfilled would stop the run there with the machine
/// half built. The same question asked first costs nothing and refuses while nothing is installed.
/// The step that writes the mirror asks it again, so the same guard holds when that step is run on
/// its own.
///
/// **Only two states are refusals, and both are fixed by editing one file and running again.** A
/// secrets file written with the line endings of another operating system keeps an invisible
/// character inside every value, and what that produces is a rejected credential that looks
/// perfectly correct on screen. A credential that is blank or still the placeholder the example file
/// ships is not a credential.
///
/// **Everything else passes, and each for its own reason.** The machine that HOSTS the registry
/// cannot pull through it — the registry does not exist yet at this point in its own install. A
/// machine whose registry address cannot be derived would have no mirror to write. And a machine
/// with no secrets file at all is the unattended base install of a cluster the secrets reach later.
///
/// **These two states are refused rather than warned for one measured reason.** A machine without
/// the mirror sends every pull to the rate-limited public path with no further sign of it, and
/// nothing later comes back to write the mirror on its own.
final class PreflightDockerMirrorCredential extends ObservingStep {
  /// Decides whether the machine in [repository] can pull through the mirror.
  const PreflightDockerMirrorCredential({required this.repository});

  /// Builds the step from what the program gave it.
  factory PreflightDockerMirrorCredential.fromArguments(Arguments arguments) =>
      PreflightDockerMirrorCredential(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation is generated in, which carries the cluster's own "
          'profile and its secrets',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Which stage this machine runs, what it is reached at and where the registry stands are three
  /// things one installation states about itself, so none of them can be written into a program
  /// file that ships to every installation.
  static const List<String> answers = <String>[stageAnswer, fqdnAnswer, buildPlaneAnswer];

  /// The name the stage is answered under, which is what names the secrets file.
  static const String stageAnswer = 'stage';

  /// The name the domain this cluster answers under is answered under.
  static const String fqdnAnswer = 'fqdn';

  /// The name the cluster hosting the registry is answered under.
  static const String buildPlaneAnswer = 'build_plane';

  /// The value in the secrets file that carries the pull credential.
  static const String credentialKey = 'REGISTRY_PULL_DOCKERCONFIGJSON';

  /// What the example secrets file ships in its place.
  static const String placeholderPrefix = 'BASE64_OF_';

  /// The checkout this installation is generated in.
  final String repository;

  /// Where the profile naming the registry lives.
  String get profilePath => '$repository/cluster/profile.yaml';

  /// Where the secrets file lives.
  String secretsPathIn(StepContext context) =>
      '$repository/secrets/secrets.${context.answers.text(stageAnswer)}';

  /// Whether this cluster hosts the registry rather than pulling through it.
  ///
  /// An empty build plane means this cluster is its own, which is what a single-cluster
  /// installation answers.
  static bool hostsTheRegistry(StepContext context) {
    final String fqdn = context.answers.text(fqdnAnswer);
    final String buildPlane = context.answers.text(buildPlaneAnswer);
    return (buildPlane.isEmpty ? fqdn : buildPlane) == fqdn;
  }

  /// The address of the registry this cluster pulls through, or null when it cannot be derived.
  ///
  /// Read out of the profile and never composed from any domain. The profile is where the value is
  /// written when the installation branch is stamped, and composing it here would produce a second
  /// answer that only agrees with the first by accident.
  static Future<String?> registryHost(StepContext context, String profilePath) async {
    if (!await context.files.exists(profilePath)) {
      return null;
    }
    final YamlNode profile;
    try {
      profile = loadYamlNode(await context.files.read(profilePath));
    } on YamlException {
      return null;
    }
    YamlNode? at = profile;
    for (final String key in <String>['global', 'endpoints', 'registry', 'host']) {
      if (at case final YamlMap map) {
        at = map.nodes[key];
        continue;
      }
      return null;
    }
    if (at?.value case final String host) {
      return host.trim().isEmpty ? null : host.trim();
    }
    return null;
  }

  /// The credential the secrets file at [path] carries for [host], or a refusal saying why not.
  ///
  /// The file is read into values here and never into this program's own environment. A secrets file
  /// that is run rather than read puts every value in it into everything the run starts afterwards.
  ///
  /// The credential itself is returned and never written anywhere a record can reach.
  static Future<PullCredential> readCredential(
    StepContext context,
    String path,
    String host,
  ) async {
    final String text = await context.files.read(path);
    if (text.contains('\r\n')) {
      return const PullCredential.refused(
        'it is written with the line endings of another operating system, which leaves an invisible '
        'character inside every value in it — what that produces is a credential that is rejected '
        'and looks perfectly correct on screen. Rewrite it with plain line endings.',
      );
    }

    final String? written = _value(text, credentialKey);
    if (written == null || written.isEmpty) {
      return const PullCredential.refused(
        '$credentialKey is blank, and without it the mirror would answer every pull with a refusal '
        'and fall back to the rate-limited public path anyway',
      );
    }
    if (written.startsWith(placeholderPrefix)) {
      return const PullCredential.refused(
        '$credentialKey is still the placeholder the example file ships, which is not a credential',
      );
    }

    final String? blob = _blobFor(written, host);
    if (blob == null) {
      return PullCredential.refused(
        '$credentialKey does not carry a credential for $host — it holds the encoded pull '
        'configuration, and the entry for that address is what the mirror is written with',
      );
    }
    return PullCredential.usable(blob);
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (hostsTheRegistry(context)) {
      return const CheckResult.satisfied(
        'this cluster hosts the registry itself, and at this point in its own install that registry '
        'does not exist — so nothing pulls through a mirror here',
      );
    }

    final String secrets = secretsPathIn(context);
    final String? host = await registryHost(context, profilePath);
    if (host == null) {
      return CheckResult.satisfied(
        "the registry's address is not readable from $profilePath, so no mirror is written and "
        'pulls stay on the public path',
      );
    }
    if (!await context.files.exists(secrets)) {
      context.log.warn(
        '$secrets is not on this machine, so no mirror is written and every pull goes to the '
        'rate-limited public path. That is the unattended base install of a cluster whose secrets '
        'arrive later; fill the file in and run this program again to write the mirror.',
      );
      return const CheckResult.satisfied('there is no secrets file on this machine yet');
    }

    final PullCredential credential = await readCredential(context, secrets, host);
    if (credential.refusal case final String refusal) {
      return CheckResult.blocked('$secrets: $refusal');
    }
    return CheckResult.satisfied('$secrets carries a usable pull credential for $host');
  }

  /// The value written for [key] in [text], or null when it is not there.
  static String? _value(String text, String key) {
    for (final String line in text.split('\n')) {
      final String trimmed = line.trim();
      if (trimmed.startsWith('#') || !trimmed.startsWith('$key=')) {
        continue;
      }
      String value = trimmed.substring(key.length + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }

  /// The credential [written] holds for [host], or null when it holds none.
  static String? _blobFor(String written, String host) {
    final Object? configuration;
    try {
      configuration = jsonDecode(utf8.decode(base64.decode(written)));
    } on FormatException {
      return null;
    }
    if (configuration is! Map<String, Object?>) {
      return null;
    }
    final Object? auths = configuration['auths'];
    if (auths is! Map<String, Object?>) {
      return null;
    }
    final Object? entry = auths[host];
    if (entry is! Map<String, Object?>) {
      return null;
    }
    final Object? blob = entry['auth'];
    return blob is String && blob.isNotEmpty ? blob : null;
  }
}

/// What a secrets file said about the pull credential.
final class PullCredential {
  /// A credential that can be used.
  const PullCredential.usable(String this.blob) : refusal = null;

  /// No usable credential, because [refusal].
  const PullCredential.refused(String this.refusal) : blob = null;

  /// The credential itself, or null when there is none.
  ///
  /// Never written to the log or to a plan. It reaches exactly one place: the file the mirror is
  /// configured in, which only its owner may read.
  final String? blob;

  /// Why there is none, or null when there is one.
  final String? refusal;
}
