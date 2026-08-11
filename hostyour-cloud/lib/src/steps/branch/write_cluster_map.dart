import 'package:ansiwise_api/ansiwise_api.dart';
import 'master_part.dart';
import 'require_installation_domain.dart';

/// Writes the one file that states what this cluster is.
///
/// Everything that has to tell one installation from another reads this file: which stage it runs,
/// which role it holds, where it builds, which apex its units sit below, where its alerts go and
/// which catalog its tenants deploy from. Nothing else states those values, which is why the file is
/// written whole from the answers this run was given rather than edited in place.
///
/// **It runs after the branch is cut and before the role is applied.** After, because the map is
/// this branch's own file and travels with it. Before, because applying the role reads this file as
/// its only input — the branch name gives the domain, and the map gives everything else.
///
/// **The one field it does not own is preserved.** A cluster release writes `release:`; this never
/// mints one and must never drop one. When that was got wrong the pin silently disappeared on every
/// rewrite, and the tooling that syncs an installation branch refused the cluster for carrying no
/// pin until somebody cut a new release.
///
/// **Every value is checked against the same grammar its neighbours are.** A domain that is not one
/// is committed as easily as a domain that is, and surfaces much later — at the first image pull
/// that cannot resolve a build plane, or at a stage called `production` that no path anywhere
/// matches. All of the problems are reported at once, because an operator fixing a map one refusal
/// per run is an operator running it five times.
final class WriteClusterMap extends ReversibleStep<String?> with FileStep {
  /// Writes the map of the cluster this run was told about.
  const WriteClusterMap({required this.repository, required this.stages});

  /// Builds the step from what the program gave it.
  factory WriteClusterMap.fromArguments(Arguments arguments) => WriteClusterMap(
    repository: arguments.text('repository'),
    stages: arguments.textList('stages'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
    ArgumentSpec(
      name: 'stages',
      kind: ArgumentKind.textList,
      describes: 'every stage the product carries, of which this installation is exactly one',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[
    'fqdn',
    'stage',
    'role',
    'master',
    'build_plane',
    'unit_apex',
    'platform_domain',
    'alert_recipients',
    'catalog_repo',
    'post_url',
  ];

  /// The two roles a cluster map may state, read off the rule that owns them.
  static const List<String> roles = MasterPart.roles;

  /// The checkout the map is written in.
  final String repository;

  /// Every stage the product carries.
  ///
  /// The product's own list and the same on every installation, which is why it stays an argument
  /// while the one stage of this installation is an answer.
  final List<String> stages;

  @override
  String pathFor(StepContext context) =>
      '$repository/clusters/active/${context.answers.text('fqdn')}.yaml';

  /// `0644` — everything that reads a cluster map reads this file.
  @override
  int get mode => 0x1a4;

  @override
  Future<CheckResult> check(StepContext context) async {
    final List<String> wrong = _problems(context);
    if (wrong.isNotEmpty) {
      return CheckResult.blocked('this installation does not describe itself: ${wrong.join('; ')}');
    }
    return super.check(context);
  }

  @override
  Future<FileContent> contentFor(StepContext context) async {
    final Arguments given = context.answers;
    final String? pin = await _release(context);
    return FileContent.text(
      <String>[
        '# What this cluster is.',
        '#',
        '# Written by the run that generated this branch, and read by everything that has to tell one',
        '# installation from another. Nothing else states these values.',
        'fqdn: ${given.text('fqdn')}',
        'stage: ${given.text('stage')}',
        'role: ${given.text('role')}',
        if (_master(context) case final String held) 'master: $held',
        'build-plane: ${given.text('build_plane')}',
        'unit-apex: ${given.text('unit_apex')}',
        'platform-domain: ${given.text('platform_domain')}',
        'alert-recipients: ${given.textList('alert_recipients').join(', ')}',
        'catalog-repo: ${given.text('catalog_repo')}',
        // Absent rather than empty when this installation has no mail service. An empty value
        // satisfies a chart that requires the key with something nothing can be reached at, which is
        // worse than the missing key a gate reports by name.
        if (_postUrl(context) case final String url) 'post-url: $url',
        // Not identity, and not this step's to write: a cluster release puts it here and a rewrite
        // hands it back untouched.
        if (pin case final String held) 'release: $held',
        '',
      ].join('\n'),
    );
  }

  /// What the map held before this run wrote it, which is what [undo] writes back.
  ///
  /// It carries the release pin the answer to [_release] is read out of, so putting these bytes back
  /// puts the pin back with them. Null is a branch that carried no map for this domain, and that is
  /// the one case where taking the write back means removing the file.
  @override
  Future<String?> capture(StepContext context) => contentBefore(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      // Nothing held this file before this run, so taking it back means removing it.
      await context.files.delete(pathFor(context));
      return;
    }
    await context.files.write(pathFor(context), captured, mode: mode);
  }

  /// The release pin the map already carries, or null when it carries none.
  Future<String?> _release(StepContext context) async {
    final String path = pathFor(context);
    if (!await context.files.exists(path)) {
      return null;
    }
    final Match? pinned = _pin.firstMatch(await context.files.read(path));
    return pinned?.group(1)?.trim();
  }

  /// The cluster this run named as holding the master part, or null when it named none.
  ///
  /// Read through the rule that owns the pair, so what this map writes and what refuses an illegal
  /// pair cannot come to disagree about which answers are blank.
  static String? _master(StepContext context) => MasterPart.of(context.answers).named;

  /// This installation's mail service, or null when it has none.
  static String? _postUrl(StepContext context) => _given(context, 'post_url');

  static String? _given(StepContext context, String name) {
    final String? value = context.answers.optionalText(name);
    return value == null || value.isEmpty ? null : value;
  }

  /// Everything about these values that would make an unusable installation, all of it at once.
  List<String> _problems(StepContext context) {
    final Arguments given = context.answers;
    final String stage = given.text('stage');
    final String role = given.text('role');
    final String fqdn = given.text('fqdn');
    final String buildPlane = given.text('build_plane');
    final String unitApex = given.text('unit_apex');
    final String platformDomain = given.text('platform_domain');
    final List<String> alertRecipients = given.textList('alert_recipients');
    final String catalogRepo = given.text('catalog_repo');
    final String? master = _master(context);

    return <String>[
      if (!stages.contains(stage))
        '"$stage" is not a stage — this product carries ${stages.join(', ')}',
      if (!roles.contains(role)) '"$role" is not a role — a cluster is ${roles.join(' or ')}',
      if (!RequireInstallationDomain.isFqdn(fqdn)) 'the domain "$fqdn" is not a domain name',
      if (!RequireInstallationDomain.isFqdn(buildPlane))
        'the build plane "$buildPlane" is not a domain name',
      if (!RequireInstallationDomain.isFqdn(unitApex))
        'the unit apex "$unitApex" is not a domain name',
      if (!RequireInstallationDomain.isFqdn(platformDomain))
        'the platform domain "$platformDomain" is not a domain name',
      // Both halves of the pair rule, asked of the object that owns it rather than written out
      // here. A map that states the opposite of what was meant is what either half produces, and a
      // copy of the rule beside the file it guards is a copy that can drift from the other readers.
      ...MasterPart.of(context.answers).problems,
      if (master case final String held)
        if (!RequireInstallationDomain.isFqdn(held)) 'the master "$held" is not a domain name',
      if (alertRecipients.isEmpty)
        'no alert recipient — every alert route that resolves to nobody stops the render of the '
            'whole observability app, naming a values key instead of this map',
      for (final String recipient in alertRecipients)
        if (!_mailbox.hasMatch(recipient.trim())) '"$recipient" is not a mailbox',
      // Nothing composes this value: the catalog is a repository this cloud does not own, and
      // without it the tenant generators read their member charts from nowhere, a release bump
      // pushes tenant pins nowhere, and the registry reaper searches nowhere. None of the three
      // says so.
      if (!_ownerAndName.hasMatch(catalogRepo))
        'the catalog "$catalogRepo" is not an owner and a name',
    ];
  }
}

/// The release pin, as a cluster release writes it.
final RegExp _pin = RegExp(r'^release:[ \t]*(\S.*)$', multiLine: true);

/// Something before an at sign, and a dotted name after it.
final RegExp _mailbox = RegExp(r'^[^@\s]+@[^@\s.]+(\.[^@\s.]+)+$');

/// An owner and a repository name, which is what a catalog is named by.
final RegExp _ownerAndName = RegExp(r'^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$');
