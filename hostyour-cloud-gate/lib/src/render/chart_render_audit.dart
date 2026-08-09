import 'package:yaml/yaml.dart';

import '../helm/helm.dart';
import '../installation.dart';
import '../tree/source_tree.dart';
import 'application_catalog.dart';
import 'chart_family.dart';
import 'render_finding.dart';
import 'rendered_manifest.dart';
import 'value_stack.dart';

/// Every chart of a tree renders, the way ArgoCD renders it.
///
/// This repository is 300 files of Helm charts and ArgoCD manifests that a cluster turns into
/// objects byte for byte. Nothing here is compiled and nothing here is run before it is deployed,
/// so a chart that does not render is found by the cluster, on a real installation, at the moment
/// somebody needed it to work.
///
/// FOUR THINGS ARE DECIDED, and the first three are what makes the fourth mean anything. A render
/// audit that walked over the charts nothing deploys, or over a catalog entry pointing at a
/// directory that is not there, would report a sound tree while the deployment of it was broken —
/// and would report exactly the same thing if it had rendered nothing at all.
final class ChartRenderAudit {
  /// The audit of [tree], rendering through [helm], with [installationValues] standing in for what
  /// an installation supplies.
  ChartRenderAudit({required this.tree, required this.helm, required this.installationValues})
    : _catalog = ApplicationCatalog(tree);

  /// The tree being decided about.
  final SourceTree tree;

  /// How a chart is turned into manifests.
  final Helm helm;

  /// The native path of the file standing in for the two install-branch positions of every stack.
  final String installationValues;

  final ApplicationCatalog _catalog;

  /// How many renders came back. Zero after [findings] has run is itself a finding, and the caller
  /// reads this to say so.
  int get rendersPerformed => _rendersPerformed;
  int _rendersPerformed = 0;

  /// The stages this TREE carries, read from the per-stage values files under platform/.
  ///
  /// The same answer the renders are driven by, and that is the point: [SourceTree.stagesCarried] is
  /// what [ValueStack] asks too, so the work and the expectation cannot come from different places
  /// and disagree. What this name is still for is saying so in a test — a reader holding the render
  /// count against something wants to see where the number came from.
  List<String> get stagesDeclared => tree.stagesCarried;

  /// How many renders this tree ASKS for: every chart, for every stage it is rendered at, at every
  /// size it carries.
  ///
  /// The count a caller holds [rendersPerformed] against. Equality and not a floor: a floor is
  /// satisfied by one render per chart, which is exactly the state a stage collapse produces.
  int get rendersExpected {
    int wanted = 0;
    for (final String app in charts) {
      final ChartFamily family = _catalog.familyOf(app);
      if (family == ChartFamily.unrendered) {
        continue;
      }
      final ValueStack stack = ValueStack(
        tree: tree,
        family: family,
        installationValues: installationValues,
      );
      wanted += stack.stagesRendered.length * stack.sizesOf(app).length;
    }
    return wanted;
  }

  /// Every chart directory under apps/, sorted.
  List<String> get charts => tree.namesDirectlyUnder('apps');

  /// Everything wrong with how this tree renders.
  List<RenderFinding> findings() => <RenderFinding>[
    ...installationStateOnTheTrunk(),
    ...catalogEntriesWithoutACharts(),
    ...togglesWithoutACatalogEntry(),
    ...chartsNothingDeploys(),
    ...renders(),
  ];

  /// The two install-branch positions of the stack, found standing on the trunk.
  ///
  /// The fixture substitutes for exactly these, and the substitution is only lossless while the
  /// trunk really is empty here. Asserted rather than assumed, because an installation's own values
  /// arriving on the trunk is both a defect in itself and the thing that would make every render
  /// below prove less than it claims.
  List<RenderFinding> installationStateOnTheTrunk() => <RenderFinding>[
    for (final String path in tree.pathsUnder('cluster/values'))
      InstallationStateOnTheTrunk(
        path: path,
        why:
            'branch-classes.yaml declares cluster/values/ trunk-absent, because the trunk is not '
            'a machine and has no answers for any of it',
      ),
    if (_clusterProfileGlobals() > 0)
      const InstallationStateOnTheTrunk(
        path: 'cluster/profile.yaml',
        why: 'it is one cluster\'s own file and the trunk carries it as `global: {}`',
      ),
  ];

  /// Catalog names with no chart directory behind them.
  List<RenderFinding> catalogEntriesWithoutACharts() => <RenderFinding>[
    for (final String stage in stages)
      for (final String name in _catalog.namesAt(stage))
        if (!tree.holds('apps/$name/Chart.yaml')) CatalogNamesNoChart(stage: stage, app: name),
  ];

  /// Deploy toggles that name an app no catalog carries.
  List<RenderFinding> togglesWithoutACatalogEntry() {
    final Set<String> known = _catalog.everyCatalogName.toSet();
    final List<RenderFinding> found = <RenderFinding>[];
    for (final String path in tree.pathsUnder('cluster/apps')) {
      final String? text = tree.textOf(path);
      if (text == null) {
        continue;
      }
      final Object? document = loadYaml(text);
      final Object? name = document is YamlMap ? document['name'] : null;
      if (name is! String) {
        found.add(ToggleNamesNoCatalogEntry(path: path, named: null));
      } else if (!known.contains(name)) {
        found.add(ToggleNamesNoCatalogEntry(path: path, named: name));
      }
    }
    return found;
  }

  /// Charts under apps/ that no ArgoCD manifest names.
  List<RenderFinding> chartsNothingDeploys() => <RenderFinding>[
    for (final String app in charts)
      if (_catalog.familyOf(app) == ChartFamily.unrendered) ChartNothingDeploys(app),
  ];

  /// Every chart rendered, for every stage and every size it carries.
  List<RenderFinding> renders() {
    if (!helm.available) {
      return const <RenderFinding>[NothingCouldBeRendered('helm is not on PATH')];
    }

    final HelmOutcome repositories = helm.addRepositories(_upstreamRepositories());
    if (repositories is HelmRefused) {
      return <RenderFinding>[
        NothingCouldBeRendered(
          'the chart repositories apps/*/Chart.yaml names could not be added '
          '(${repositories.reason})',
        ),
      ];
    }

    final List<RenderFinding> found = <RenderFinding>[];
    for (final String app in charts) {
      final ChartFamily family = _catalog.familyOf(app);
      if (family == ChartFamily.unrendered) {
        continue;
      }

      final HelmOutcome vendored = helm.vendorDependencies(tree.nativePathOf('apps/$app'));
      if (vendored is HelmRefused) {
        found.add(
          ChartDidNotRender(
            app: app,
            stage: 'every stage',
            size: null,
            reason: 'its dependencies could not be vendored: ${vendored.reason}',
          ),
        );
        continue;
      }

      final ValueStack stack = ValueStack(
        tree: tree,
        family: family,
        installationValues: installationValues,
      );
      for (final String stage in stack.stagesRendered) {
        for (final String? size in stack.sizesOf(app)) {
          final HelmOutcome outcome = helm.render(stack.renderOf(app, stage, size: size));
          switch (outcome) {
            case HelmRefused(:final String reason):
              found.add(ChartDidNotRender(app: app, stage: stage, size: size, reason: reason));
            case HelmProduced(:final String manifest):
              _rendersPerformed += 1;
              final Map<int, List<String>> rejections = RenderedManifest(manifest).rejections;
              for (final MapEntry<int, List<String>> rejection in rejections.entries) {
                for (final String missing in rejection.value) {
                  found.add(
                    RenderedDocumentRejected(
                      app: app,
                      stage: stage,
                      size: size,
                      document: rejection.key,
                      missing: missing,
                    ),
                  );
                }
              }
          }
        }
      }
    }
    return found;
  }

  /// Every chart repository the charts of this tree name.
  ///
  /// Derived from the Chart.yaml files rather than listed anywhere, so a new upstream dependency
  /// needs no edit here and cannot be the reason a render is reported broken.
  Set<String> _upstreamRepositories() {
    final Set<String> urls = <String>{};
    for (final String app in charts) {
      final String? chart = tree.textOf('apps/$app/Chart.yaml');
      if (chart == null) {
        continue;
      }
      for (final RegExpMatch match in _httpsRepository.allMatches(chart)) {
        final String? url = match.group(1);
        if (url != null) {
          urls.add(url);
        }
      }
    }
    return urls;
  }

  int _clusterProfileGlobals() {
    final String? text = tree.textOf('cluster/profile.yaml');
    if (text == null) {
      return 0;
    }
    final Object? document = loadYaml(text);
    final Object? globals = document is YamlMap ? document['global'] : null;
    return globals is YamlMap ? globals.length : 0;
  }
}

final RegExp _httpsRepository = RegExp(r'repository:\s*(https://\S+)');
