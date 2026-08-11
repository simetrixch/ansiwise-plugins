// A test may read the real files and start a real process; the rule that confines `dart:io` is
// about the shipped library. A test that rendered a chart it had pasted in would be measuring the
// paste.
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The two ends of one answer, made to meet: the step that writes the profile and the chart tree
/// that reads it.
///
/// **What this exists for.** `global.alertRecipients` is written by one thing and read by another,
/// in two different repositories, and nothing joined them. The chart resolved an enabled alert route
/// to the trunk's empty list and stopped the render of the whole observability application, while
/// every unit test on either side stayed green — the step's tests asserted on text the step wrote,
/// and the chart had no test at all.
///
/// **So this renders the REAL chart tree against the REAL bytes the step produced.** The profile is
/// not written here: [StampClusterProfile] writes it into a fake machine and those bytes are put on
/// disk unchanged. The values chain is the one
/// `argocd/<stage>/apps/applicationset.yaml` gives every app — the platform files, then the app's
/// own, then `cluster/profile.yaml` last, which is what lets the profile win over the trunk.
///
/// **The vendored subchart is replaced by the source one.** `apps/observability/charts` carries a
/// packaged copy of `charts/monitoring`, and rendering that copy would prove the copy. The chart
/// under test is the tree in `charts/monitoring`.
///
/// **Two directions, permanently.** One installation names mailboxes and the application renders
/// carrying them; one names none and the render stops, naming the key. Without the second, a chart
/// that had quietly stopped consulting the key would still pass the first.
void main() {
  late final String chartTree;
  late final String helm;
  setUpAll(() {
    chartTree = _chartTree();
    helm = _helm();
  });

  /// The profile [StampClusterProfile] writes for one master cluster, byte for byte.
  Future<String> profileFor({required List<String> alertRecipients}) async {
    const String repository = '/srv/hostyour-cloud';
    const String fqdn = 'm1.example.com';
    final StepContext context = StepContext(
      step: const StepName('stamp'),
      arguments: const Arguments(<String, Object>{'repository': repository}),
      answers: Arguments(<String, Object>{
        'fqdn': fqdn,
        'role': 'master',
        'build_plane': fqdn,
        'unit_apex': 'units.example.com',
        'platform_domain': 'example.com',
        'alert_recipients': alertRecipients,
        'tailnet_url': 'https://tailnet.example.com',
        'post_url': 'https://post.$fqdn',
      }),
      facts: Facts.none,
      shell: FakeShell(),
      files: FakeFiles(<String, String>{}),
      http: FakeHttp(),
      clock: FakeClock(),
      entropy: FakeEntropy(),
      log: const _SilentLog(),
    );

    await const StampClusterProfile(repository: repository).apply(context);
    return (context.files as FakeFiles)
        .contents['$repository/${StampClusterProfile.pathInRepository}']!;
  }

  /// The observability application rendered against [profile], through the real values chain.
  ProcessResult renderWith(String profile) {
    final Directory work = Directory.systemTemp.createTempSync('hostyour-observability-');
    addTearDown(() => work.deleteSync(recursive: true));

    final String app = p.join(work.path, 'observability');
    _copyInto(Directory(p.join(chartTree, 'apps', 'observability')), Directory(app));
    // The packaged copy out, the tree under test in. Both under charts/ would load the same subchart
    // twice.
    File(p.join(app, 'charts', 'monitoring-2.0.0.tgz')).deleteSync();
    _copyInto(
      Directory(p.join(chartTree, 'charts', 'monitoring')),
      Directory(p.join(app, 'charts', 'monitoring')),
    );

    final String profilePath = p.join(work.path, 'profile.yaml');
    File(profilePath).writeAsStringSync(profile);

    return Process.runSync(helm, <String>[
      'template',
      'observability',
      app,
      '--values', p.join(chartTree, 'platform', 'values-common.yaml'),
      '--values', p.join(chartTree, 'platform', 'values-dev.yaml'),
      '--values', p.join(app, 'values-common.yaml'),
      '--values', p.join(app, 'values-dev.yaml'),
      // Last, which is what makes this file the installation's own word on every global.* key.
      '--values', profilePath,
    ]);
  }

  test('the answered mailboxes reach the rendered alert route', () async {
    final ProcessResult rendered = renderWith(
      await profileFor(alertRecipients: <String>['alerts@example.com', 'ops@example.com']),
    );

    expect(
      rendered.exitCode,
      0,
      reason: 'the observability application did not render: ${rendered.stderr}',
    );
    final String out = rendered.stdout as String;
    expect(out, contains('kind: AlertmanagerConfig'));
    expect(out, contains('name: platform-default'));
    // The mailboxes themselves, on the field Alertmanager delivers to. The trunk carries an empty
    // list under the same key and stands earlier in the chain, so their being here is the profile
    // winning and not the product's default.
    expect(out, contains('- to: "alerts@example.com"'));
    expect(out, contains('- to: "ops@example.com"'));
  });

  test('a mailbox a plain scalar would swallow reaches the rendered alert route', () async {
    // `#ops@example.com` passes the grammar the cluster map holds mailboxes to, and written
    // unquoted it is a YAML comment: the recipient would be absent from the rendered route while
    // the render itself stayed green, because the other recipient still resolves.
    final ProcessResult rendered = renderWith(
      await profileFor(alertRecipients: <String>['#ops@example.com', 'alerts@example.com']),
    );

    expect(
      rendered.exitCode,
      0,
      reason: 'the observability application did not render: ${rendered.stderr}',
    );
    expect(rendered.stdout, contains('- to: "#ops@example.com"'));
  });

  test('an installation that answered no mailbox stops the render, naming the key', () async {
    // The other direction, kept permanently. A chart that stopped consulting global.alertRecipients
    // would still pass the test above, because an entry with its own `emails` renders too.
    final ProcessResult rendered = renderWith(await profileFor(alertRecipients: const <String>[]));

    expect(rendered.exitCode, isNot(0), reason: 'a route that reaches nobody rendered as healthy');
    expect(rendered.stderr, contains('resolves to no recipient'));
    expect(rendered.stderr, contains('global.alertRecipients'));
  });
}

/// Where the chart tree an installation deploys is checked out, proven to be there.
///
/// **The charts are not this package's.** They are the product tree one installation deploys, in
/// its own repository; this package ships the steps that turn that tree into one installation. The
/// fallback is one relative path from the directory `dart test` runs in, and every checkout here
/// sits at the same depth below the directory they share.
///
/// **Absent FAILS and the refusal says what it looked for.** A suite that skipped this render would
/// report green over the one thing it exists to measure — that the file the step writes and the
/// chart that reads it agree — and that is the shape the defect it covers already had.
String _chartTree() {
  final String tree = Platform.environment[chartTreeVariable] ?? '../../hostyour-cloud';
  if (!Directory('$tree/charts/monitoring').existsSync()) {
    throw StateError(
      'no chart tree at $tree — this test renders the charts an installation deploys against the '
      'profile this package writes, and they live in their own repository. Clone it beside this '
      'one, or set $chartTreeVariable to where it is.',
    );
  }
  return tree;
}

/// The environment variable that names the chart tree, overriding the fallback.
const String chartTreeVariable = 'HOSTYOUR_CLOUD_TREE';

/// The renderer, proven to be runnable.
///
/// Nothing else can answer what a chart produces from a set of values: the templates are Go
/// templates and the values chain is Helm's own coalescing. A reimplementation here would be a
/// second renderer that can disagree with the one a cluster runs.
String _helm() {
  final ProcessResult found = Process.runSync('helm', <String>['version', '--short']);
  if (found.exitCode != 0) {
    throw StateError('helm answered ${found.exitCode} to `helm version --short`: ${found.stderr}');
  }
  return 'helm';
}

/// Everything under [from], copied into [to].
void _copyInto(Directory from, Directory to) {
  to.createSync(recursive: true);
  for (final FileSystemEntity entity in from.listSync()) {
    final String name = p.basename(entity.path);
    if (entity is Directory) {
      _copyInto(entity, Directory(p.join(to.path, name)));
    } else if (entity is File) {
      entity.copySync(p.join(to.path, name));
    }
  }
}

/// A log that keeps nothing: this test asserts on what the chart renders, not on what a step says.
final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}
