import 'package:ansiwise_api/ansiwise_api.dart';

/// Decides which of the platform's applications run on THIS cluster.
///
/// Every application has a toggle under `cluster/apps/<name>.yaml` carrying one line, `deploy:`, and
/// the ApplicationSet renders an Application only where it says `"true"`. On the trunk they carry a
/// generic default, because the trunk is not a cluster and cannot know.
///
/// **Three of them are decided by what this cluster IS, and the rest are not decided here at all.**
/// That distinction is the whole of this step:
///
/// - the **build plane** set — the registry, what builds into it, and what is only useful beside it
///   — runs on exactly ONE cluster of an installation, because promoting an image from test to prod
///   reuses the same built image and a second builder would produce a second one
/// - the **master** set is provided once for the whole installation: the tailnet coordinator every
///   host logs in to, and the central observability stack
/// - the **agent** is the mirror of that last one: a cluster without the master part has no local
///   Grafana, Prometheus or Loki and pushes to the one that has
///
/// Everything else keeps whatever the trunk says. Those are an operator's decisions — whether this
/// installation wants a database browser, a mail relay — and a stamper that overwrote them would
/// undo a choice somebody made on the branch, silently, on the next run.
///
/// **It rewrites the line and nothing else.** Each of these files is mostly the paragraph explaining
/// what the application is and when it belongs on a cluster; that paragraph is the only place an
/// operator learns it, and a step that regenerated the file whole would replace it with whatever the
/// step's author remembered.
final class StampAppToggles extends ReversibleStep {
  /// Rewrites the toggles of the cluster this run was told about.
  const StampAppToggles({required this.repository});

  /// Builds the step from what the program gave it.
  factory StampAppToggles.fromArguments(Arguments arguments) =>
      StampAppToggles(repository: arguments.text('repository'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose install branch is being made into one installation',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['fqdn', 'role', 'build_plane'];

  /// The applications that run on the build plane and nowhere else.
  ///
  /// tekton, the registry and image-builder are the plane itself; consumer-build is one build
  /// namespace per registered unit, which only means anything where the registry and the
  /// EventListener are; gate-runner references image-builder's shared clone Task; and the manager
  /// is deployed beside the registry it pushes to.
  static const List<String> onTheBuildPlane = <String>[
    'consumer-build',
    'gate-runner',
    'image-builder',
    'manager',
    'registry',
    'tekton',
  ];

  /// The applications provided once per installation, by the cluster holding the master part.
  static const List<String> whereTheMasterIs = <String>['tailnet-coordinator', 'observability'];

  /// The applications that run exactly where the master part is NOT.
  ///
  /// One entry, and it is the mirror of `observability` above: a cluster without the master part
  /// runs the light push agent instead of the full stack, and running both would have it scraping
  /// itself and shipping the result to itself.
  static const List<String> whereTheMasterIsNot = <String>['observability-agent'];

  /// The checkout the toggles are rewritten in.
  final String repository;

  /// Where a toggle lives.
  String pathOf(String app) => '$repository/cluster/apps/$app.yaml';

  /// What each toggle this step owns must say, given what this cluster is.
  Map<String, bool> decisionsFor(StepContext context) {
    final Arguments given = context.answers;
    final bool holdsMaster = given.text('role') == 'master';
    final bool isTheBuildPlane = given.text('build_plane') == given.text('fqdn');
    return <String, bool>{
      for (final String app in onTheBuildPlane) app: isTheBuildPlane,
      for (final String app in whereTheMasterIs) app: holdsMaster,
      for (final String app in whereTheMasterIsNot) app: !holdsMaster,
    };
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, bool> wanted = decisionsFor(context);
    final List<String> missing = <String>[];
    final List<String> wrong = <String>[];

    for (final MapEntry<String, bool> decision in wanted.entries) {
      final String path = pathOf(decision.key);
      if (!await context.files.exists(path)) {
        // A toggle this step decides and the tree does not carry is a defect in the tree, not a
        // state to write around: the ApplicationSet matches on the file, so an absent one means the
        // application is unreachable however this run answers.
        missing.add(decision.key);
        continue;
      }
      if (_deployIn(await context.files.read(path)) != decision.value) {
        wrong.add(decision.key);
      }
    }

    if (missing.isNotEmpty) {
      return CheckResult.blocked(
        'there is no toggle for ${missing.join(', ')} — the ApplicationSet matches on that file, so '
        'those applications can reach no cluster',
      );
    }
    if (wrong.isEmpty) {
      return const CheckResult.satisfied(
        'every toggle this cluster decides already says what it is',
      );
    }
    context.log.info('${wrong.length} toggle(s) do not match this cluster: ${wrong.join(', ')}');
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final Map<String, bool> wanted = decisionsFor(context);
    final List<String> before = <String>[];
    final List<String> after = <String>[];
    for (final MapEntry<String, bool> decision in wanted.entries) {
      final String path = pathOf(decision.key);
      if (!await context.files.exists(path)) {
        continue;
      }
      final bool now = _deployIn(await context.files.read(path));
      if (now != decision.value) {
        before.add('cluster/apps/${decision.key}.yaml: deploy "$now"');
        after.add('cluster/apps/${decision.key}.yaml: deploy "${decision.value}"');
      }
    }
    if (before.isEmpty) {
      return const StepPlan.nothing('every toggle this cluster decides already says what it is');
    }
    // One step rewrites one line in up to nine files, and a plan carries one path — so the path is
    // the directory they share and the difference is the lines that would change in it.
    return StepPlan.diff(
      '$repository/cluster/apps',
      before: before.join('\n'),
      after: after.join('\n'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    for (final MapEntry<String, bool> decision in decisionsFor(context).entries) {
      final String path = pathOf(decision.key);
      final String before = await context.files.read(path);
      final String after = _withDeploy(before, decision.value);
      if (after != before) {
        await context.files.write(path, after, mode: 0x1a4);
      }
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    // Every one of these files is on the trunk, so taking the stamp back is restoring what git
    // holds. Restoring them in one call rather than one at a time: a partial undo leaves a cluster
    // whose toggles half describe it, which is the one state neither this step nor the operator can
    // reason about.
    final List<String> argv = <String>[
      '-C',
      repository,
      'checkout',
      '--',
      for (final String app in decisionsFor(context).keys) 'cluster/apps/$app.yaml',
    ];
    final CommandResult restored = await context.shell.run(Command('git', argv));
    if (!restored.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: restored.exitCode,
        stderr: restored.stderr,
      );
    }
  }

  /// What the `deploy:` line of [content] says.
  ///
  /// Anything that is not the word true — including a missing line — reads as false, which is what
  /// the ApplicationSet does with it: it renders an Application only on `"true"`.
  static bool _deployIn(String content) {
    for (final String line in content.split('\n')) {
      final Match? found = _deploy.firstMatch(line);
      if (found != null) {
        return found.group(1)!.replaceAll('"', '').replaceAll("'", '').trim() == 'true';
      }
    }
    return false;
  }

  /// [content] with its `deploy:` line saying [value], and every other byte untouched.
  static String _withDeploy(String content, bool value) {
    final List<String> lines = content.split('\n');
    for (int i = 0; i < lines.length; i++) {
      if (_deploy.hasMatch(lines[i])) {
        lines[i] = 'deploy: "$value"';
        return lines.join('\n');
      }
    }
    // A toggle whose file carries no such line at all: the line is added rather than the file
    // rewritten, so the paragraph explaining the application survives.
    return '${content.trimRight()}\ndeploy: "$value"\n';
  }

  /// The one line this step owns. Anchored at the start so a mention of `deploy:` inside the
  /// explanatory paragraph above it is not mistaken for the setting.
  static final RegExp _deploy = RegExp(r'^deploy:\s*(.*)$');
}
