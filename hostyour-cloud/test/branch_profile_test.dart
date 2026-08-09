import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// What makes an install branch one installation rather than the product tree.
///
/// The trunk carries `global: {}` and every toggle at a generic default, because it is not a cluster
/// and cannot know. These two steps are what turn that into a description of ONE cluster — and until
/// they existed, two steps of `deploy-cluster` read a profile nobody wrote.
void main() {
  const String repo = '/srv/hostyour-cloud';

  /// A run told what one cluster is.
  StepContext contextFor({
    required String fqdn,
    required String role,
    String? master,
    required String buildPlane,
    String? postUrl,
    Map<String, String> files = const <String, String>{},
    FakeShell? shell,
  }) => StepContext(
    step: const StepName('stamp'),
    arguments: const Arguments(<String, Object>{'repository': repo}),
    answers: Arguments(<String, Object>{
      'fqdn': fqdn,
      'role': role,
      'master': ?master,
      'build_plane': buildPlane,
      'unit_apex': 'units.example.com',
      'platform_domain': 'example.com',
      'tailnet_url': 'https://tailnet.example.com',
      'post_url': ?postUrl,
    }),
    facts: Facts.none,
    shell: shell ?? FakeShell(),
    files: FakeFiles(<String, String>{...files}),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
  );

  group('the profile', () {
    Future<String> profileFor(StepContext context) async {
      const StampClusterProfile step = StampClusterProfile(repository: repo);
      await step.apply(context);
      return (context.files as FakeFiles).contents['$repo/cluster/profile.yaml']!;
    }

    test('a master describes itself', () async {
      final String out = await profileFor(
        contextFor(fqdn: 'm1.example.com', role: 'master', buildPlane: 'm1.example.com'),
      );

      expect(out, contains('domain: m1.example.com'));
      expect(out, contains('clusterName: m1'));
      expect(out, contains('booksBranch: m1.example.com'));
      expect(out, contains('vaultUrl: https://vault.m1.example.com'));
      expect(out, contains('vaultKubernetesAuthPath: kubernetes-m1'));
    });

    test('a slave points its books, its Vault and its tailnet at the master', () async {
      // The failure this prevents: a slave pointed at its own empty Vault, which answers, and
      // answers wrongly, so nothing reports it until a secret cannot be resolved.
      final String out = await profileFor(
        contextFor(
          fqdn: 's1.example.com',
          role: 'slave',
          master: 'm1.example.com',
          buildPlane: 'm1.example.com',
        ),
      );

      expect(out, contains('domain: s1.example.com'));
      expect(out, contains('booksBranch: m1.example.com'));
      expect(out, contains('vaultUrl: https://vault.m1.example.com'));
      // Its own short name, not the master's — the auth mount is per cluster.
      expect(out, contains('vaultKubernetesAuthPath: kubernetes-s1'));
    });

    test('the registry follows the BUILD PLANE, not the master and not this cluster', () async {
      // Two different questions. A cluster can hold the master part and not be the build plane, and
      // deriving one from the other is how an image pull reaches a registry that is not there.
      final String out = await profileFor(
        contextFor(fqdn: 'm1.example.com', role: 'master', buildPlane: 'b1.example.com'),
      );

      expect(out, contains('host: zot.b1.example.com'));
      expect(out, contains('registry: false'), reason: 'the registry does not run here');
      expect(out, contains('vault: true'), reason: 'the master part does');
    });

    test('servicesLocal says what runs HERE, per service', () async {
      final String out = await profileFor(
        contextFor(
          fqdn: 'b1.example.com',
          role: 'slave',
          master: 'm1.example.com',
          buildPlane: 'b1.example.com',
        ),
      );

      expect(out, contains('registry: true'));
      expect(out, contains('vault: false'));
      expect(out, contains('observabilityCentral: false'));
    });

    test('no mail service means the key is ABSENT, not empty', () async {
      // An empty value satisfies a chart that requires the key with something nothing can be
      // reached at, which is worse than the missing key a gate reports by name.
      final String out = await profileFor(
        contextFor(fqdn: 'm1.example.com', role: 'master', buildPlane: 'm1.example.com'),
      );

      expect(out.contains('post:'), isFalse);
    });

    test('a slave that names no master is refused rather than described with holes', () async {
      const StampClusterProfile step = StampClusterProfile(repository: repo);

      final CheckResult result = await step.check(
        contextFor(fqdn: 's1.example.com', role: 'slave', buildPlane: 'm1.example.com'),
      );

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('nowhere for its books'));
    });
  });

  group('the toggles', () {
    /// The nine toggles this step owns, as the trunk carries them.
    Map<String, String> trunkToggles() => <String, String>{
      for (final String app in <String>[
        ...StampAppToggles.onTheBuildPlane,
        ...StampAppToggles.whereTheMasterIs,
        ...StampAppToggles.whereTheMasterIsNot,
      ])
        '$repo/cluster/apps/$app.yaml':
            '# The paragraph that explains what this application is.\nname: $app\ndeploy: "false"\n',
    };

    Future<Map<String, bool>> togglesAfter(StepContext context) async {
      const StampAppToggles step = StampAppToggles(repository: repo);
      await step.apply(context);
      final FakeFiles files = context.files as FakeFiles;
      return <String, bool>{
        for (final String app in step.decisionsFor(context).keys)
          app: files.contents['$repo/cluster/apps/$app.yaml']!.contains('deploy: "true"'),
      };
    }

    test('the build plane set runs where the build plane is, and nowhere else', () async {
      final Map<String, bool> onIt = await togglesAfter(
        contextFor(
          fqdn: 'b1.example.com',
          role: 'slave',
          master: 'm1.example.com',
          buildPlane: 'b1.example.com',
          files: trunkToggles(),
        ),
      );
      final Map<String, bool> elsewhere = await togglesAfter(
        contextFor(
          fqdn: 's2.example.com',
          role: 'slave',
          master: 'm1.example.com',
          buildPlane: 'b1.example.com',
          files: trunkToggles(),
        ),
      );

      for (final String app in StampAppToggles.onTheBuildPlane) {
        expect(onIt[app], isTrue, reason: '$app belongs on the build plane');
        expect(elsewhere[app], isFalse, reason: '$app must run on exactly one cluster');
      }
    });

    test('the coordinator and the central stack are provided once, by the master', () async {
      final Map<String, bool> master = await togglesAfter(
        contextFor(
          fqdn: 'm1.example.com',
          role: 'master',
          buildPlane: 'm1.example.com',
          files: trunkToggles(),
        ),
      );

      expect(master['tailnet-coordinator'], isTrue);
      expect(master['observability'], isTrue);
    });

    test('THE AGENT IS THE MIRROR: it runs exactly where the full stack does not', () async {
      // Getting this pair backwards gives a cluster that scrapes itself and ships the result to
      // itself, or one with no observability at all — and both look like a working deployment.
      final Map<String, bool> master = await togglesAfter(
        contextFor(
          fqdn: 'm1.example.com',
          role: 'master',
          buildPlane: 'm1.example.com',
          files: trunkToggles(),
        ),
      );
      final Map<String, bool> slave = await togglesAfter(
        contextFor(
          fqdn: 's1.example.com',
          role: 'slave',
          master: 'm1.example.com',
          buildPlane: 'm1.example.com',
          files: trunkToggles(),
        ),
      );

      expect(master['observability'], isTrue);
      expect(master['observability-agent'], isFalse);
      expect(slave['observability'], isFalse);
      expect(slave['observability-agent'], isTrue);
    });

    test('a toggle this step does not own is not touched', () async {
      // Whether an installation wants a database browser or a mail relay is an operator's decision
      // taken on the branch, and a stamper that overwrote it would undo that choice silently on the
      // next run.
      final StepContext context = contextFor(
        fqdn: 'm1.example.com',
        role: 'master',
        buildPlane: 'm1.example.com',
        files: <String, String>{
          ...trunkToggles(),
          '$repo/cluster/apps/dbgate.yaml': 'name: dbgate\ndeploy: "false"\n',
        },
      );
      const StampAppToggles(repository: repo).decisionsFor(context);
      await const StampAppToggles(repository: repo).apply(context);

      expect(
        (context.files as FakeFiles).contents['$repo/cluster/apps/dbgate.yaml'],
        contains('deploy: "false"'),
      );
    });

    test('the explanatory paragraph survives — only the one line changes', () async {
      final StepContext context = contextFor(
        fqdn: 'm1.example.com',
        role: 'master',
        buildPlane: 'm1.example.com',
        files: trunkToggles(),
      );

      await const StampAppToggles(repository: repo).apply(context);
      final String out =
          (context.files as FakeFiles).contents['$repo/cluster/apps/tailnet-coordinator.yaml']!;

      // That paragraph is the only place an operator learns when the application belongs on a
      // cluster; a step that regenerated the file whole would replace it with whatever its author
      // remembered.
      expect(out, contains('# The paragraph that explains what this application is.'));
      expect(out, contains('name: tailnet-coordinator'));
      expect(out, contains('deploy: "true"'));
    });

    test('a toggle the tree does not carry is refused, not written around', () async {
      final Map<String, String> incomplete = trunkToggles()
        ..remove('$repo/cluster/apps/registry.yaml');

      final CheckResult result = await const StampAppToggles(repository: repo).check(
        contextFor(
          fqdn: 'm1.example.com',
          role: 'master',
          buildPlane: 'm1.example.com',
          files: incomplete,
        ),
      );

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('registry'));
    });

    test('a second run is a no-op', () async {
      final StepContext context = contextFor(
        fqdn: 'm1.example.com',
        role: 'master',
        buildPlane: 'm1.example.com',
        files: trunkToggles(),
      );

      await const StampAppToggles(repository: repo).apply(context);
      final CheckResult again = await const StampAppToggles(repository: repo).check(context);

      expect(again, isA<Satisfied>());
    });
  });
}

/// A log that keeps nothing: these tests assert on what the steps WRITE, not on what they say.
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
