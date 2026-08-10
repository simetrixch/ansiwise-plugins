import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Installs or converges one helm release, pinned to a chart version.
///
/// **The version is pinned and there is no path that resolves the newest.** An unpinned upgrade asks
/// the repository what the latest is on every run, and that answer can cross a major version by
/// itself — on a component nothing but a re-run of this program repairs.
///
/// **Both the version and the values decide whether an upgrade runs.** Keying the decision on the
/// chart version alone is a recorded defect with no symptom: an operator edits the release's values,
/// re-runs, sees green and gets nothing, because the version already matched. So the values the
/// release is currently holding are read back and compared with the file, and a difference in either
/// is work to do.
final class HelmRelease extends IrreversibleStep {
  /// Installs [chart] at [chartVersion] as [release] in [namespace].
  const HelmRelease({
    required this.release,
    required this.chart,
    required this.chartVersion,
    required this.namespace,
    this.values,
  });

  /// Builds the step from what the program gave it.
  factory HelmRelease.fromArguments(Arguments arguments) => HelmRelease(
    release: arguments.text('release'),
    chart: arguments.text('chart'),
    chartVersion: arguments.text('chart_version'),
    namespace: arguments.text('namespace'),
    values: arguments.optionalText('values'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'release',
      kind: ArgumentKind.text,
      describes: 'the name helm holds this installation of the chart under',
    ),
    ArgumentSpec(
      name: 'chart',
      kind: ArgumentKind.text,
      describes: 'the chart, as the repository name and the chart name',
    ),
    ArgumentSpec(
      name: 'chart_version',
      kind: ArgumentKind.text,
      describes:
          'the exact chart version, which is never left out — an unpinned upgrade can cross a '
          'major version on a component nothing else repairs',
    ),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the release is installed into',
    ),
    ArgumentSpec(
      name: 'values',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the values file this release is configured by, when it has one',
    ),
  ];

  /// The release name.
  final String release;

  /// The chart, as `<repository>/<chart>`.
  final String chart;

  /// The pinned chart version.
  final String chartVersion;

  /// The namespace it goes into.
  final String namespace;

  /// The values file, or null when the chart's own defaults are what is wanted.
  final String? values;

  /// The chart's own name, without the repository in front of it.
  ///
  /// What helm reports back is `<chart>-<version>`, so the repository has to come off before the two
  /// can be compared.
  String get chartName => chart.contains('/') ? chart.split('/').last : chart;

  @override
  String get irreversibleReason =>
      'helm removes what it installed and nothing else: the volume claims this chart\'s stateful '
      'sets bound stay behind holding whatever the release wrote, and a later install lands on top '
      'of that rather than on an empty cluster';

  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, Object?>? installed = await _installed(context);
    if (installed == null) {
      return const CheckResult.ready();
    }

    final Object? status = installed['status'];
    if (status != 'deployed') {
      return const CheckResult.ready();
    }

    final Object? held = installed['chart'];
    final String wanted = '$chartName-$chartVersion';
    if (held != wanted) {
      context.log.debug('the installed chart is $held and this run pins $wanted');
      return const CheckResult.ready();
    }

    final String? path = values;
    if (path == null) {
      return CheckResult.satisfied('$release is deployed at $wanted');
    }
    if (!await context.files.exists(path)) {
      return CheckResult.blocked('$path is not on this machine, and $release is configured by it');
    }

    final Object? wantedValues = _plain(loadYaml(await context.files.read(path)));
    final Object? currentValues = await _currentValues(context);
    if (jsonEncode(wantedValues) != jsonEncode(currentValues)) {
      context.log.debug('$release is at $wanted and the values it holds differ from $path');
      return const CheckResult.ready();
    }
    return CheckResult.satisfied('$release is deployed at $wanted with the values in $path');
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_upgrade);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult done = await context.shell.run(
      Command.detailed(
        'helm',
        arguments: _upgrade.sublist(1),
        // A chart that pulls its own dependencies and a cluster that is slow to admit them make this
        // the longest single call of the whole program. Explicit, because waiting forever is the
        // default and a hung upgrade is indistinguishable from one that is working.
        timeout: const Duration(minutes: 15),
      ),
    );
    if (!done.ok) {
      throw CommandFailed(argv: _upgrade, exitCode: done.exitCode, stderr: done.stderr);
    }
  }

  List<String> get _upgrade => <String>[
    'helm',
    'upgrade',
    '--install',
    release,
    chart,
    '--namespace',
    namespace,
    '--version',
    chartVersion,
    if (values case final String path) ...<String>['--values', path],
  ];

  /// What helm holds under this release name in this namespace, or null when it holds nothing.
  Future<Map<String, Object?>?> _installed(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      Command.observing('helm', <String>['list', '--namespace', namespace, '-o', 'json']),
    );
    if (!listed.ok || listed.trimmed.isEmpty) {
      return null;
    }
    final Object? decoded = _decoded(listed.trimmed);
    if (decoded is! List<Object?>) {
      return null;
    }
    for (final Object? entry in decoded) {
      if (entry is Map<String, Object?> && entry['name'] == release) {
        return entry;
      }
    }
    return null;
  }

  /// The values the release is currently holding, as helm gives them back.
  Future<Object?> _currentValues(StepContext context) async {
    final CommandResult got = await context.shell.run(
      Command.observing('helm', <String>[
        'get',
        'values',
        release,
        '--namespace',
        namespace,
        '-o',
        'json',
      ]),
    );
    return got.ok ? _decoded(got.trimmed) : null;
  }

  static Object? _decoded(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// A YAML document as the plain maps and lists a comparison can be made over.
  ///
  /// `loadYaml` returns its own node types, and two of them holding the same content are not equal
  /// to each other or to anything a JSON decoder produced.
  static Object? _plain(Object? node) {
    if (node is YamlMap) {
      return <String, Object?>{
        for (final MapEntry<Object?, Object?> pair in node.entries)
          '${pair.key}': _plain(pair.value),
      };
    }
    if (node is YamlList) {
      return <Object?>[for (final Object? element in node) _plain(element)];
    }
    return node;
  }
}
