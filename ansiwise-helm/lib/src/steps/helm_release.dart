import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'ambiguous_scalar.dart';
import 'helm_command.dart';

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
    this.helm = const <String>['helm'],
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory HelmRelease.fromArguments(Arguments arguments) => HelmRelease(
    release: arguments.text('release'),
    chart: arguments.text('chart'),
    chartVersion: arguments.text('chart_version'),
    namespace: arguments.text('namespace'),
    values: arguments.optionalText('values'),
    helm: arguments.textList('helm_command'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    helmCommandArgument,
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
    elevationArgument,
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

  /// How helm is reached on this machine, as the program and any arguments before helm's own.
  final List<String> helm;

  /// The chart's own name, without the repository in front of it.
  ///
  /// What helm reports back is `<chart>-<version>`, so the repository has to come off before the two
  /// can be compared.
  String get chartName => chart.contains('/') ? chart.split('/').last : chart;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  String get irreversibleReason =>
      'helm removes what it installed and nothing else: the volume claims this chart\'s stateful '
      'sets bound stay behind holding whatever the release wrote, and a later install lands on top '
      'of that rather than on an empty cluster';

  @override
  Future<CheckResult> check(StepContext context) async {
    // EVERY DECISION TO ACT NAMES WHAT IT READ, at info, because the default record keeps nothing
    // quieter. The run this was added for had an upgrade exit 0 and install nothing: the step then
    // failed its own post-check, and the record held four exit codes and not one measurement —
    // output is kept only for a command that failed or a row that said `keep_output`, and every
    // command had answered 0. An operator reading that record could not see what the step saw, and
    // the unwind then sent them to the repository row above, where nothing was wrong. These lines
    // are the measurement: what the listing named, which chart was held against which, so a reader
    // sees why the step decided the work was still to do.
    final List<Map<String, Object?>>? releases = await _releases(context);
    final Map<String, Object?>? installed = _entryFor(releases);
    if (installed == null) {
      context.log.info(_absentFrom(releases));
      return const CheckResult.ready();
    }

    final Object? status = installed['status'];
    if (status != 'deployed') {
      context.log.info('$release is listed with status $status, and this step produces deployed');
      return const CheckResult.ready();
    }

    final Object? held = installed['chart'];
    final String wanted = '$chartName-$chartVersion';
    if (held != wanted) {
      context.log.info('the installed chart is $held and this run pins $wanted');
      return const CheckResult.ready();
    }

    final String? path = values;
    if (path == null) {
      return CheckResult.satisfied('$release is deployed at $wanted');
    }
    if (!await context.files.exists(path, elevated: elevated)) {
      return CheckResult.blocked('$path is not on this machine, and $release is configured by it');
    }

    final String written = await context.files.read(path, elevated: elevated);

    // WHAT THE TWO READERS OF THIS FILE DISAGREE ABOUT, refused before it is read as agreement.
    //
    // helm parses YAML 1.1 and this parses YAML 1.2, and a handful of scalars mean different things
    // to the two. Without this the release installs perfectly and the comparison below compares
    // helm's meaning with this one, finds them different, upgrades, asks again and gets the same
    // answer — reporting on every run, forever, that the step ran and the machine is not in the
    // state it produces. Measured on a machine, where it stopped a program at step 6 of 64.
    //
    // Blocked rather than reported, because there is nothing this row can do about it: the file has
    // to say which of the two it means, and only whoever wrote it knows.
    final List<AmbiguousScalar> ambiguous = ambiguousScalarsIn(written);
    if (ambiguous.isNotEmpty) {
      return CheckResult.blocked(
        '$path is read by helm and by this step, and they do not agree on '
        '${ambiguous.length == 1 ? 'one value' : '${ambiguous.length} values'}: '
        '${ambiguous.map((AmbiguousScalar each) => each.sentence).join('; ')}. '
        'Quote what is meant as text, or write the number the way both read alike — 256 rather '
        'than 0400 — or this release can never be reported as installed',
      );
    }

    final Object? wantedValues = _plain(loadYaml(written));
    final Object? currentValues = await _currentValues(context);
    if (_canonical(wantedValues) != _canonical(currentValues)) {
      context.log.info('$release is at $wanted and the values it holds differ from $path');
      return const CheckResult.ready();
    }
    return CheckResult.satisfied('$release is deployed at $wanted with the values in $path');
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_upgrade);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult done = await context.shell.run(
      helmCommand(
        helm,
        // `_upgrade` is the whole invocation including how helm is reached, because that is what a
        // plan shows the operator. What is handed on here is helm's own half of it.
        _upgrade.sublist(helm.length),
        // A chart that pulls its own dependencies and a cluster that is slow to admit them make this
        // the longest single call of the whole program. Explicit, because waiting forever is the
        // default and a hung upgrade is indistinguishable from one that is working.
        timeout: const Duration(minutes: 15),
      ),
    );
    if (!done.ok) {
      throw CommandFailed(argv: _upgrade, exitCode: done.exitCode, stdout: '', stderr: done.stderr);
    }
  }

  List<String> get _upgrade => <String>[
    ...helm,
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

  /// Every release helm lists in [namespace], or null when the listing itself did not answer.
  ///
  /// The whole listing and not only the entry this step is after, because the listing is what the
  /// step READ, and a decision to act is reported with what it was made on. An entry alone cannot
  /// say the difference between "the release is not among these" and "helm answered nothing".
  Future<List<Map<String, Object?>>?> _releases(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      helmCommand(helm, <String>['list', '--namespace', namespace, '-o', 'json'], observes: true),
    );
    if (!listed.ok || listed.trimmed.isEmpty) {
      return null;
    }
    final Object? decoded = _decoded(listed.trimmed);
    if (decoded is! List<Object?>) {
      return null;
    }
    return <Map<String, Object?>>[
      for (final Object? entry in decoded)
        if (entry is Map<String, Object?>) entry,
    ];
  }

  /// The entry [releases] holds under this release name, or null when it holds none.
  Map<String, Object?>? _entryFor(List<Map<String, Object?>>? releases) {
    for (final Map<String, Object?> entry in releases ?? const <Map<String, Object?>>[]) {
      if (entry['name'] == release) {
        return entry;
      }
    }
    return null;
  }

  /// What the listing said, when [release] was not in it — the record's line, not a verdict.
  String _absentFrom(List<Map<String, Object?>>? releases) {
    if (releases == null) {
      return 'the listing of $namespace did not answer, so nothing shows $release is installed';
    }
    if (releases.isEmpty) {
      return 'helm lists no releases in $namespace, so $release is not installed';
    }
    final String named = releases
        .map((Map<String, Object?> entry) => '${entry['name']}')
        .join(', ');
    return 'helm lists $named in $namespace, and $release is not among them';
  }

  /// The values the release is currently holding, as helm gives them back.
  ///
  /// OBSERVING, like the listing above it and for the same reason: asking a release what values it
  /// holds changes nothing. Undeclared, the planning ports refuse it — and because the refusal
  /// happens inside `check`, the whole step becomes unmeasurable in the two modes whose entire
  /// purpose is measuring, while reporting something else entirely. It cost a machine run to find,
  /// and what made it findable was `keep_output: true` on the row putting the refusal in the record.
  Future<Object?> _currentValues(StepContext context) async {
    final CommandResult got = await context.shell.run(
      helmCommand(helm, <String>[
        'get',
        'values',
        release,
        '--namespace',
        namespace,
        '-o',
        'json',
      ], observes: true),
    );
    return got.ok ? _decoded(got.trimmed) : null;
  }

  /// [value] as text that two equal shapes always produce, whatever order they were written in.
  ///
  /// **A map has no order and `jsonEncode` gives it one.** The same keys written differently encode
  /// differently, so comparing encoded strings answers "these are not equal" for two things that are.
  /// The values file is read in the order somebody typed it and helm gives back its own — so the
  /// comparison was never equal, every release configured by a values file failed its own
  /// post-check, the run unwound, and the unwind removed the chart repository the row above had
  /// registered. The next attempt then failed at the release with "repo not found" and pointed at
  /// the repository row, where nothing was wrong.
  ///
  /// Every map is sorted by key, at every depth. A list keeps its order, because a list has one.
  static String _canonical(Object? value) => jsonEncode(_sorted(value));

  static Object? _sorted(Object? value) {
    if (value case final Map<Object?, Object?> map) {
      final List<String> keys = map.keys.map((Object? k) => '$k').toList()..sort();
      return <String, Object?>{for (final String key in keys) key: _sorted(map[key])};
    }
    if (value case final List<Object?> items) {
      return <Object?>[for (final Object? item in items) _sorted(item)];
    }
    return value;
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
  ///
  /// **TWO READERS READ THE VALUES FILE, AND THEY DO NOT AGREE ON EVERY SPELLING.** helm follows
  /// YAML 1.1; this reader follows YAML 1.2. Where a value is spelled differently under the two,
  /// the release holds one number and this comparison expects another, and the step reports a
  /// release that installed perfectly as "still not in the state it produces" — on every run, with
  /// no way to make it stop. Measured: `0400` is 256 to helm and 400 here, and `yes` is true to helm
  /// and the text "yes" here.
  ///
  /// Neither reader is wrong and neither can be made to imitate the other, so the rule is about the
  /// FILE: a values file handed to this step is written in the subset both agree on — a plain
  /// decimal rather than a leading zero, `true` and `false` rather than `yes` and `no`. Nothing
  /// enforces that yet, and until something does this paragraph is what the next person has.
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
