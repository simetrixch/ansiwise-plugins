import 'package:ansiwise_api/ansiwise_api.dart';
import 'filled_template.dart';
import 'filled_template_step.dart';

/// Puts the credentials this run was given into the file that seeds this installation's Vault.
///
/// `secrets/secrets.<stage>` is where the credentials a third party issues stand until Vault
/// has been seeded from them: the two repository credentials, the DNS token, the storage box, and
/// the four the cluster carrying the build plane needs. None of them can be generated and none of
/// them can be derived — they are obtained from GitHub, from Cloudflare and from Hetzner, and this
/// step is how an answer a run was given reaches that file.
///
/// **A key that already carries a value is left exactly as it stands, and that is why this step is
/// not a plain write.** Only an empty key, an absent one, or one still holding exactly what the
/// template ships is filled — the last of the three because a file somebody copied and never filled
/// looks filled. The file is this installation's hand-filled input: an operator opens it and types
/// into it, each key under the paragraph of the template that says what to obtain and where. A run
/// that wrote every key from its own answers would replace what somebody typed with whatever the
/// interview happened to carry, and a credential rotated by hand would go back to the one it was
/// rotated away from.
///
/// **What that costs, said here rather than left to be discovered: an answer given to a LATER run
/// does not reach a key that already carries something.** The file keeps the value it has, the seed
/// keeps writing that value into Vault, and nothing reports a difference because there is none —
/// the two agree on the old value. Changing a credential of a running installation is an edit to
/// this file, not a different answer to a re-run.
///
/// **What this file does NOT hold, because an operator keeping it as their disaster copy would be
/// keeping the wrong one.** Vault's root token and its unseal keys are written by the step that
/// initializes Vault, into the credential file that step is given, and never here — they exist
/// nowhere else, and this file is not that place. The identity provider's credentials are generated
/// by the seed row that puts them into Vault and pass through no file at all. Nor does any later
/// phase add to this one: this step is the only step of the installation that writes it, so what it
/// holds after an install is what an operator and this step put in it.
///
/// **The values never reach the record.** A plan carries the names of the keys it would fill and,
/// for a credential, [Redactor.marker] in place of the value; the file itself is written only by a
/// real run. The values also never cross a command line — nothing here runs a command at all, and
/// the file is produced as text and handed to the file port.
///
/// **The four of the build plane are demanded only on the cluster that carries it.** Every other
/// cluster reads its images through that one and would never look at them, so asking there would be
/// asking for a credential nothing on the machine ever uses.
final class WriteStageSecrets extends FilledTemplateStep {
  /// Writes the credentials of the installation generated in [repository].
  const WriteStageSecrets({required this.repository});

  /// Builds the step from what the program gave it.
  factory WriteStageSecrets.fromArguments(Arguments arguments) =>
      WriteStageSecrets(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[
    'fqdn',
    'stage',
    'build_plane',
    'gitops_repo_pat',
    'gitops_repo_read_pat',
    'cloudflare_api_token',
    'storage_box_host',
    'storage_box_user',
    'storage_box_password',
    'registry_dockerhub_user',
    'registry_dockerhub_token',
    'build_hostyour_cloud_repo_pat',
    'build_catalog_repo_pat',
  ];

  /// Which answer stands behind each key of the file, for the keys every cluster carries.
  static const Map<String, String> everyCluster = <String, String>{
    'GITOPS_REPO_PAT': 'gitops_repo_pat',
    'GITOPS_REPO_READ_PAT': 'gitops_repo_read_pat',
    'CLOUDFLARE_API_TOKEN': 'cloudflare_api_token',
    'STORAGE_BOX_HOST': 'storage_box_host',
    'STORAGE_BOX_USER': 'storage_box_user',
    'STORAGE_BOX_PASSWORD': 'storage_box_password',
  };

  /// The same, for the keys only the cluster carrying the build plane ever reads.
  static const Map<String, String> buildPlaneOnly = <String, String>{
    'REGISTRY_DOCKERHUB_USER': 'registry_dockerhub_user',
    'REGISTRY_DOCKERHUB_TOKEN': 'registry_dockerhub_token',
    'BUILD_HOSTYOUR_CLOUD_REPO_PAT': 'build_hostyour_cloud_repo_pat',
    'BUILD_CATALOG_REPO_PAT': 'build_catalog_repo_pat',
  };

  /// The keys whose value must not appear in a plan, a log or a run record.
  ///
  /// The other two name a machine and an account on it. They are what an operator checks a dry run
  /// against, and hiding them would make the plan unreadable for no gain.
  static const List<String> credentials = <String>[
    'GITOPS_REPO_PAT',
    'GITOPS_REPO_READ_PAT',
    'CLOUDFLARE_API_TOKEN',
    'STORAGE_BOX_PASSWORD',
    'REGISTRY_DOCKERHUB_TOKEN',
    'BUILD_HOSTYOUR_CLOUD_REPO_PAT',
    'BUILD_CATALOG_REPO_PAT',
  ];

  /// The checkout the file is written in.
  final String repository;

  /// The file the trunk carries, with every value at a placeholder.
  @override
  String get templatePath => '$repository/secrets/secrets.example';

  /// `0600` — every value in this file is a credential, so only its owner may read it.
  @override
  int get mode => 0x180;

  /// Where the credentials of [context]'s stage stand.
  @override
  String pathFor(StepContext context) =>
      '$repository/secrets/secrets.${context.answers.text('stage')}';

  /// Whether this cluster carries the build plane, and so reads the four of it.
  bool carriesTheBuildPlane(StepContext context) =>
      context.answers.text('build_plane') == context.answers.text('fqdn');

  /// What this step writes, by the key the file declares it under.
  ///
  /// An answer nobody gave is not in the map at all, so the key keeps whatever the template ships
  /// rather than being set to the empty string — the two read the same to a shell and only one of
  /// them says "nobody answered this".
  @override
  Map<String, String> valuesFrom(StepContext context) {
    final Arguments given = context.answers;
    return <String, String>{
      for (final MapEntry<String, String> pair in <String, String>{
        ...everyCluster,
        if (carriesTheBuildPlane(context)) ...buildPlaneOnly,
      }.entries)
        if (given.optionalText(pair.value) case final String value)
          if (value.isNotEmpty) pair.key: value,
    };
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(templatePath)) {
      return CheckResult.blocked(
        '$templatePath is not on this branch, and it is what this file is made from — it declares '
        'every key, what issues it and which rights it needs',
      );
    }

    final Map<String, String> wanted = valuesFrom(context);
    final List<String> unanswered = <String>[
      for (final MapEntry<String, String> pair in <String, String>{
        ...everyCluster,
        if (carriesTheBuildPlane(context)) ...buildPlaneOnly,
      }.entries)
        if (!wanted.containsKey(pair.key)) pair.value,
    ];
    if (unanswered.isNotEmpty) {
      return CheckResult.blocked(
        'these credentials were not given, and nothing can generate or derive one of them: '
        '${unanswered.join(', ')}'
        '${carriesTheBuildPlane(context) ? ' — this cluster carries the build plane, so the four '
                  'of the registry and the release apply to it' : ''}',
      );
    }

    final List<String> unwritable = unwritableIn(wanted);
    if (unwritable.isNotEmpty) {
      return CheckResult.blocked(
        'these credentials hold a double quote or a line break, which this file cannot carry: '
        '${unwritable.join(', ')}',
      );
    }

    final FilledTemplate file = await read(context);
    final List<String> undeclared = file.missingKeys(wanted.keys);
    if (undeclared.isNotEmpty) {
      return CheckResult.blocked(
        '$templatePath declares no ${undeclared.join(', ')}, and a key it does not declare cannot '
        'be filled in place — the seed reads this file by the schema at the foot of the template',
      );
    }

    if (toFill(file, wanted).isEmpty) {
      return CheckResult.satisfied(
        '${pathFor(context)} carries every credential this installation was given',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // Answered rather than thrown, on the one machine this step cannot act on at all. A plan is what
    // an operator reads to decide whether to let the run happen, and a plan that fails to be
    // produced tells them nothing about what would be done.
    if (!await context.files.exists(templatePath)) {
      return StepPlan.nothing(
        '$templatePath is not on this branch, so nothing can be filled from it',
      );
    }

    final FilledTemplate file = await read(context);
    final Map<String, String> wanted = valuesFrom(context);
    final List<String> filling = toFill(file, wanted);

    for (final String key in wanted.keys) {
      context.log.debug(
        filling.contains(key)
            ? '$key would be filled in'
            : '$key already carries a value and would be left alone',
      );
    }

    // A plan is read out of the run record, and this file's values are the credentials of a whole
    // installation. So the difference carried here is the KEYS this step would fill and never their
    // values — the same shape a step that rewrites many files uses, where the plan names the tree
    // and the difference is what would change in it.
    return StepPlan.diff(
      pathFor(context),
      before: filling.map((String key) => '$key=').join('\n'),
      after: filling
          .map(
            (String key) =>
                '$key=${credentials.contains(key) ? Redactor.marker : wanted[key] ?? ''}',
          )
          .join('\n'),
    );
  }
}
