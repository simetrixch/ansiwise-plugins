import 'package:ansiwise_api/ansiwise_api.dart';

/// Writes the one file every chart reads to learn where this installation's services are.
///
/// The trunk carries `global: {}` — it is the product tree and knows no installation, so it can name
/// no host. Every application's ArgoCD Application loads this file LAST in its values chain, so what
/// stands here wins over everything the product declares. That is what makes one tree serve two
/// companies.
///
/// **Two steps read it and, until this existed, nothing wrote it.** `preflight_docker_mirror_
/// credential` reads `global.endpoints.registry.host` and `configure_slave_apiserver_oidc_trust`
/// reads `global.vaultUrl`, both during `deploy-cluster`. An install branch cut without this file
/// rendered carries the trunk's empty map, and those two steps then read a profile nobody wrote.
///
/// **Rendered from the answers, not parsed back out of the cluster map.** The map and this file are
/// two renderings of one set of facts, and the run holds those facts already — checked once, where
/// they were taken in. Re-reading the map would put a second YAML parser between an answer and the
/// value it produces, and a disagreement between the two would be invisible until a chart resolved
/// the wrong host.
///
/// **What follows the master part and what follows the build plane are different questions.** Vault
/// and the central observability stack run where the master role is; the registry runs on the build
/// plane; and a cluster can be one, both or neither. Deriving one from the other is how a slave ends
/// up pointed at its own empty Vault.
/// **THE KEYS THIS WRITES ARE A CONTRACT WITH THE ROWS THAT READ THEM, and nothing checks it.** The
/// steps that talk to the secret store take the profile's path and its key names from their own
/// program rows, so that a product keeping the same facts elsewhere configures them instead of
/// forking those steps. This step is the other side: it is THIS platform's, its keys are the ones
/// its charts read, and it is not configurable for the same reason the chart values are not.
///
/// The two agree today because the rows default to what is written here. An operator who moves a
/// key in a row and not here gets a run that reads nothing under the new name — and the vault steps
/// refuse by name, which is what keeps that from being silent. The obligation ends when the vault
/// steps become a package of their own: a generic one carries no default for this platform's key
/// names, so both sides then stand in this installation's program files, once.
final class StampClusterProfile extends ReversibleStep<String?> with FileStep {
  /// Writes the profile of the cluster this run was told about.
  const StampClusterProfile({required this.repository});

  /// Builds the step from what the program gave it.
  factory StampClusterProfile.fromArguments(Arguments arguments) =>
      StampClusterProfile(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose install branch is being made into one installation',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[
    'fqdn',
    'role',
    'master',
    'build_plane',
    'unit_apex',
    'platform_domain',
    'tailnet_url',
    'post_url',
  ];

  /// Where the profile stands, relative to the top of the checkout.
  ///
  /// A constant rather than a literal inside [pathFor], because the gate asks the same question of a
  /// tree it walked — whether a run writes this path again — and it used to answer by restating the
  /// literal. Two statements of one path can disagree; one cannot.
  static const String pathInRepository = 'cluster/profile.yaml';

  /// The checkout the profile is written in.
  final String repository;

  @override
  String pathFor(StepContext context) => '$repository/$pathInRepository';

  /// `0644` — every chart's render reads this file.
  @override
  int get mode => 0x1a4;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> wrong = _problems(context);
    if (wrong.isNotEmpty) {
      return CheckResult.blocked('this installation cannot be described: ${wrong.join('; ')}');
    }
    return super.check(context);
  }

  @override
  Future<FileContent> contentFor(StepContext context) async {
    final Arguments given = context.answers;
    final String fqdn = given.text('fqdn');
    final String name = _shortName(fqdn);
    final bool holdsMaster = given.text('role') == 'master';
    // Where the master role is. On a cluster that holds it, that is this cluster; on one that does
    // not, the map's `master` names it. Everything that is provided ONCE per installation — the
    // books, Vault, the tailnet coordinator, the central observability — hangs off this one answer.
    final String master = holdsMaster ? fqdn : _optional(given, 'master')!;
    final String buildPlane = given.text('build_plane');

    return FileContent.text(
      <String>[
        '# Where this installation\'s services are, and which of them run here.',
        '#',
        '# The trunk carries `global: {}` because it knows no installation. This file is written per',
        '# install branch from the cluster map, and every application loads it LAST in its values',
        '# chain — so what stands here wins over everything the product declares.',
        '#',
        '# Only global.* keys belong here: they reach every subchart through Helm\'s own `global:`',
        '# convention. An app-specific value stays in that app\'s values-<stage>.yaml.',
        'global:',
        '  domain: $fqdn',
        '  clusterName: $name',
        '  unitApex: ${given.text('unit_apex')}',
        '  platformDomain: ${given.text('platform_domain')}',
        // The install branch of the cluster holding the master role, which is where this installation
        // keeps its cluster maps and its registrations. On a slave that is a DIFFERENT branch from
        // the one this file stands on.
        '  booksBranch: $master',
        // Vault serves at vault.<domain> — apps/coredns/templates/configmap.yaml rewrites exactly
        // that name to the in-cluster Service. It follows the master part, not this cluster, or a
        // slave would be pointed at a Vault that does not run there.
        '  vaultUrl: https://vault.$master',
        '  tailnetUrl: ${given.text('tailnet_url')}',
        // Always kubernetes-<name>: the auth mount deploy-gitops creates for this cluster, and the
        // name it creates it under. One rule, so a role binding and the client that uses it cannot
        // disagree about the path.
        '  vaultKubernetesAuthPath: kubernetes-$name',
        '  endpoints:',
        '    registry:',
        // The registry runs on the build plane and is reached there by every cluster of this
        // installation, which is why it follows the build plane and not this cluster.
        '      host: zot.$buildPlane',
        if (_optional(given, 'post_url') case final String url) ...<String>[
          '    post:',
          '      url: $url',
        ],
        // Whether each service runs HERE. A chart reads this to decide between the in-cluster Service
        // and the public name — the same fact, asked from the other side.
        '  servicesLocal:',
        '    registry: ${buildPlane == fqdn}',
        '    vault: $holdsMaster',
        '    observabilityCentral: $holdsMaster',
        '',
      ].join('\n'),
    );
  }

  /// What the profile held before this run stamped it, which is what [undo] writes back.
  ///
  /// The trunk carries this file, so on a branch cut from it there is always text to put back. Null
  /// is a branch that carried none, and that is the one case where taking the stamp back means
  /// removing the file — a file every chart's render requires is never deleted because it happened
  /// to be absent from a tree nobody looked at before apply.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      await context.files.delete(pathFor(context));
      return;
    }
    await context.files.write(pathFor(context), captured, mode: mode);
  }

  /// Everything that would make an undescribable installation, all of it at once.
  List<String> _problems(StepContext context) {
    final Arguments given = context.answers;
    final List<String> wrong = <String>[];
    final String role = given.text('role');

    if (role != 'master' && role != 'slave') {
      wrong.add('the role is "$role", and a cluster holds either the master part or it does not');
    }
    // A slave with no master names no books branch, no Vault and no tailnet — three values every
    // chart requires — so it is refused here rather than producing a profile with three holes.
    if (role == 'slave' && _optional(given, 'master') == null) {
      wrong.add(
        'this cluster does not hold the master part and names no cluster that does, so there is '
        'nowhere for its books, its Vault or its tailnet to be',
      );
    }
    return wrong;
  }

  /// The first label of [fqdn] — what this cluster is called among its siblings.
  static String _shortName(String fqdn) {
    final int dot = fqdn.indexOf('.');
    return dot == -1 ? fqdn : fqdn.substring(0, dot);
  }

  /// The answer named [name], or null where it was left blank.
  ///
  /// An answer left empty and an answer nobody gave are the same thing: the client renders an
  /// optional field as an empty box, and an operator who tabbed past it sends the empty string.
  static String? _optional(Arguments given, String name) {
    final String? value = given.optionalText(name);
    return value == null || value.isEmpty ? null : value;
  }
}
