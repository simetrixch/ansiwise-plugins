import 'package:ansiwise_core/ansiwise_core.dart';

import '../declaration.dart';
import '../stamping.dart';
import '../trees.dart';
import '../upstreams.dart';

/// Reports every pin of one declaration against what its upstream has now.
///
/// **It never fails on a new upstream release, and that is its whole character.** A version
/// appearing somewhere on the internet must not turn a tree red, or red stops meaning "the tree
/// is sound" and starts meaning "nothing was published today". So this step MEASURES and never
/// mutates: run it before a release, read it, decide. The stamping is a step of its own, and the
/// choice between the two columns is a person's.
///
/// **The list is the declaration, not a second list kept here.** A component added there shows up
/// in this report without anyone editing anything else — a report that has to be extended by hand
/// goes stale exactly when it matters. The same file drives the stamp, which is what makes the
/// two sides unable to disagree about what a component is; where the stamp for a chart dependency
/// names the dependency, this report reads the repository to ask out of that same Chart.yaml,
/// because the repository a chart comes from differs per chart in ways that are easy to guess
/// wrong — two repositories of one vendor are not the same repository.
///
/// **A pin this cannot resolve prints as "?" with the reason.** That is a finding about the
/// report, not about the pin, and it says so rather than staying quiet. A pin whose declaration
/// stamps it nowhere is named too: it is a version nothing carries, which is how a pin silently
/// stops being one.
///
/// What CAN refuse this step is its own ground: a trees mapping that binds no label for the
/// declaration, or a declaration that does not parse. Those are defects of the row and the file,
/// not of the internet, and reporting around them would print a table about nothing.
final class ReportVersionPinsAgainstUpstream extends ObservingStep {
  /// Reports the pins of the declaration at [declarationPath] in tree [declarationTree].
  const ReportVersionPinsAgainstUpstream({
    required this.declarationTree,
    required this.declarationPath,
    required this.trees,
    required this.timeoutSeconds,
  });

  /// Builds the step from what the program gave it.
  factory ReportVersionPinsAgainstUpstream.fromArguments(Arguments arguments) =>
      ReportVersionPinsAgainstUpstream(
        declarationTree: arguments.text('declaration_tree'),
        declarationPath: arguments.text('declaration_path'),
        trees: TreeBinding.readFrom(arguments.raw('trees')),
        timeoutSeconds: arguments.integer('timeout_seconds'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'declaration_tree',
      kind: ArgumentKind.text,
      describes:
          'the label of the tree the declaration file lives in — a label the trees mapping below '
          'binds',
    ),
    ArgumentSpec(
      name: 'declaration_path',
      kind: ArgumentKind.text,
      describes: 'the declaration file inside that tree, whose components this reports',
    ),
    ArgumentSpec(
      name: 'trees',
      kind: ArgumentKind.mapping,
      describes:
          'where each tree label the report has to read from stands on this machine, as '
          'LABEL: {answer: name} or LABEL: {path: /srv/tree} — the report reads the declaration '
          'itself, and the Chart.yaml of every dependency whose repository it looks up',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      required: false,
      defaultValue: 25,
      describes:
          'how long one upstream request may take before its row is answered "?" instead — a '
          'report should end while its reader is still there',
    ),
  ];

  /// The label of the tree the declaration lives in.
  final String declarationTree;

  /// The declaration file inside that tree.
  final String declarationPath;

  /// Where each tree label stands, by path or by the name of the answer that holds it.
  final Map<String, TreeBinding> trees;

  /// How long one upstream request may take.
  final int timeoutSeconds;

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({Map<String, String>? roots, List<String> problems}) resolved = resolveTrees(
      trees,
      context.answers,
    );
    final Map<String, String>? roots = resolved.roots;
    if (roots == null) {
      return CheckResult.blocked(resolved.problems.join('; '));
    }
    final String? declarationRoot = roots[declarationTree];
    if (declarationRoot == null) {
      return CheckResult.blocked(
        'the declaration lives in tree "$declarationTree", and the trees mapping of this row '
        'binds no such label',
      );
    }
    final String source = underTree(declarationRoot, declarationPath);
    if (!await context.files.exists(source)) {
      return CheckResult.blocked(
        '$source is not there, and it is the declaration this report reads',
      );
    }
    final VersionsDeclaration declaration;
    try {
      declaration = parseDeclaration(await context.files.read(source), where: source);
    } on DeclarationInvalid catch (broken) {
      return CheckResult.blocked(broken.toString());
    }

    final Duration timeout = Duration(seconds: timeoutSeconds);
    final DateTime moment = context.clock.now().toUtc();
    context.log.info('pinned versions against upstream — ${moment.toIso8601String()}');
    context.log.info('this is a report; a newer upstream release is not a failure');
    int reported = 0;
    int unresolved = 0;
    for (final String group in declaration.groups) {
      context.log.info(group);
      for (final PinnedComponent component in declaration.ofGroup(group)) {
        final UpstreamReading reading = await _upstreamOf(context, component, roots, timeout);
        final StringBuffer cell = StringBuffer(reading.newest ?? '? ${reading.unresolved}');
        if (reading.caveat != null) {
          cell.write(' (${reading.caveat})');
        }
        if (component.note != null) {
          cell.write(' — ${component.note}');
        }
        if (component.stamps.isEmpty) {
          cell.write(' (stamped nowhere)');
        }
        context.log.info(
          '  ${component.name.padRight(28)} ${component.version.padRight(16)} $cell',
        );
        reported++;
        if (reading.newest == null) {
          unresolved++;
        }
      }
    }
    context.log.info(
      'a major-version jump is never a bump: read what changed and verify the render or the '
      'behaviour',
    );
    return CheckResult.satisfied(
      '$reported pin(s) reported against upstream, $unresolved of them unresolved — and a newer '
      'upstream release is not a failure',
    );
  }

  Future<UpstreamReading> _upstreamOf(
    StepContext context,
    PinnedComponent component,
    Map<String, String> roots,
    Duration timeout,
  ) async {
    final Upstream? upstream = component.upstream;
    return switch (upstream) {
      null => const UpstreamReading.unresolved('no upstream is declared'),
      final GithubRelease at => githubNewestRelease(
        context.http,
        at.project,
        at.matching,
        timeout: timeout,
      ),
      final DockerHubTags at => dockerHubNewestTag(
        context.http,
        at.image,
        at.matching,
        timeout: timeout,
      ),
      final OciTags at => registryNewestTag(
        context.http,
        at.host,
        at.image,
        at.matching,
        timeout: timeout,
      ),
      final HelmIndex at => chartNewestVersion(
        context.http,
        at.repository,
        at.chart,
        timeout: timeout,
      ),
      final SnapChannel at => snapNewestStableTrack(context.http, at.snap, timeout: timeout),
      final HashicorpRelease at => hashicorpLatestVersion(
        context.http,
        at.product,
        timeout: timeout,
      ),
      ChartRepository() => _fromStampedChart(context, component, roots, timeout),
    };
  }

  /// The repository the stamped Chart.yaml names, asked for the stamped dependency.
  Future<UpstreamReading> _fromStampedChart(
    StepContext context,
    PinnedComponent component,
    Map<String, String> roots,
    Duration timeout,
  ) async {
    final ChartDependencyStamp? stamp = component.stamps
        .whereType<ChartDependencyStamp>()
        .firstOrNull;
    if (stamp == null) {
      return const UpstreamReading.unresolved(
        'the upstream is the chart repository of the stamped dependency, and no chart_dependency '
        'stamp says which Chart.yaml to read',
      );
    }
    final String? root = roots[stamp.tree];
    if (root == null) {
      return UpstreamReading.unresolved(
        'the Chart.yaml to read lives in tree "${stamp.tree}", which this row does not map',
      );
    }
    final String path = underTree(root, stamp.file);
    if (!await context.files.exists(path)) {
      return UpstreamReading.unresolved('$path is not there');
    }
    final ({String? repository, String? whyNot}) named = chartDependencyRepository(
      await context.files.read(path),
      stamp.dependency,
    );
    final String? repository = named.repository;
    if (repository == null) {
      return UpstreamReading.unresolved('$path ${named.whyNot}');
    }
    return chartNewestVersion(context.http, repository, stamp.dependency, timeout: timeout);
  }
}
