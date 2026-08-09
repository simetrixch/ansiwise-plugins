import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// What an installation says about itself, and what that leaves it carrying.
///
/// The map is the one file that states which cluster this is. Everything after it is read from
/// there, which is why it is written after the branch exists and before anything is decided by it.
///
/// Both steps here read what an installation IS out of the run's answers rather than out of their
/// arguments, so the variation between these cases lives in the bag rather than in the constructor:
/// what the step is given by the program file is the same on every installation.
void main() {
  const String repository = '/srv/hostyour-cloud';
  const String fqdn = 'm1.example.com';
  const String trunk = 'master';
  const String mapPath = '$repository/clusters/active/$fqdn.yaml';
  const List<String> stages = <String>['dev', 'test', 'prod'];

  const WriteClusterMap writeMap = WriteClusterMap(repository: repository, stages: stages);
  const StampRole roleStep = StampRole(repository: repository, stages: stages, trunk: trunk);

  /// What an operator answered, with everything a valid installation needs already in place.
  Arguments answering({
    String domain = fqdn,
    String stage = 'dev',
    String role = 'master',
    String? master,
    String buildPlane = fqdn,
    String unitApex = 'example.com',
    String platformDomain = 'example.com',
    List<String> alertRecipients = const <String>['alerts@example.com'],
    String catalogRepo = 'example-org/tenant-catalog',
    String? postUrl,
  }) => Arguments(<String, Object>{
    'fqdn': domain,
    'stage': stage,
    'role': role,
    'master': ?master,
    'build_plane': buildPlane,
    'unit_apex': unitApex,
    'platform_domain': platformDomain,
    'alert_recipients': alertRecipients,
    'catalog_repo': catalogRepo,
    'post_url': ?postUrl,
  });

  StepContext contextOn({FakeShell? shell, FakeFiles? files, Arguments? answers}) => StepContext(
    shell: shell ?? FakeShell(),
    files: files ?? FakeFiles(),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: answers ?? answering(),
    facts: Facts.none,
  );

  group('the cluster map states what this installation is', () {
    test('every value it was answered is in the file', () async {
      final FakeFiles files = FakeFiles();
      final StepContext context = contextOn(files: files);

      await writeMap.apply(context);
      final String written = files.contents[mapPath] ?? '';

      expect(written, contains('fqdn: $fqdn'));
      expect(written, contains('stage: dev'));
      expect(written, contains('role: master'));
      expect(written, contains('build-plane: $fqdn'));
      expect(written, contains('unit-apex: example.com'));
      expect(written, contains('platform-domain: example.com'));
      expect(written, contains('alert-recipients: alerts@example.com'));
      expect(written, contains('catalog-repo: example-org/tenant-catalog'));
      expect(await writeMap.check(context), isA<Satisfied>());
    });

    test('a release pin the map already carries is written back', () async {
      // Without this the pin vanished on every rewrite, and the tooling that syncs an installation
      // branch refused the cluster for carrying no pin until somebody cut a new release.
      final FakeFiles files = FakeFiles(<String, String>{
        mapPath: 'fqdn: $fqdn\nrole: master\nrelease: 2026.07.3\n',
      });
      final StepContext context = contextOn(files: files);

      await writeMap.apply(context);
      expect(files.contents[mapPath], contains('release: 2026.07.3'));
    });

    test('a pin is never minted where there was none', () async {
      final FakeFiles files = FakeFiles();
      await writeMap.apply(contextOn(files: files));
      expect(files.contents[mapPath], isNot(contains('release:')));
    });

    test('a second run leaves the file byte-identical', () async {
      final FakeFiles files = FakeFiles(<String, String>{mapPath: 'release: 2026.07.3\n'});
      final StepContext context = contextOn(files: files);

      await writeMap.apply(context);
      final String once = files.contents[mapPath] ?? '';
      files.written.clear();

      expect(await writeMap.check(context), isA<Satisfied>());
      expect(files.written, isEmpty);
      expect(files.contents[mapPath], once);
    });

    test('a mail service that was not answered is an absent key, never an empty one', () async {
      // An empty value satisfies a chart that requires the key with something nothing can be
      // reached at, which is worse than the missing key a gate reports by name.
      final FakeFiles files = FakeFiles();
      await writeMap.apply(contextOn(files: files));
      expect(files.contents[mapPath], isNot(contains('post-url')));
    });

    test('an optional answer left blank is the same as one nobody gave', () async {
      // The client renders an optional field as an empty box, and an operator who tabbed past it
      // sends the empty string. As a value that would put "post-url: " into the map.
      final FakeFiles files = FakeFiles();
      await writeMap.apply(
        contextOn(
          files: files,
          answers: answering(postUrl: '', master: ''),
        ),
      );
      expect(files.contents[mapPath], isNot(contains('post-url')));
      expect(files.contents[mapPath], isNot(contains('master:')));
    });

    test('a mail service that was answered is written', () async {
      final FakeFiles files = FakeFiles();
      await writeMap.apply(
        contextOn(
          files: files,
          answers: answering(postUrl: 'https://post.example.com'),
        ),
      );
      expect(files.contents[mapPath], contains('post-url: https://post.example.com'));
    });

    test('a stage this product does not carry is refused before the file exists', () async {
      // A typo here used to be committed and then consumed by every reader of the map.
      final FakeFiles files = FakeFiles();

      final CheckResult answer = await writeMap.check(
        contextOn(
          files: files,
          answers: answering(stage: 'production'),
        ),
      );
      expect((answer as Blocked).reason, contains('production'));
      expect(files.contents, isEmpty);
    });

    test('a build plane is measured against the same grammar as the domain', () async {
      // It is the same kind of thing, and unchecked it surfaces much later — at the first image
      // pull of a unit that cannot resolve it.
      final CheckResult answer = await writeMap.check(
        contextOn(answers: answering(buildPlane: 'm1_build.example.com')),
      );
      expect((answer as Blocked).reason, contains('build plane'));
    });

    test('everything wrong is named at once, not one thing per run', () async {
      final CheckResult answer = await writeMap.check(
        contextOn(
          answers: answering(
            stage: 'production',
            role: 'controller',
            buildPlane: 'not a domain',
            alertRecipients: <String>['nobody'],
            catalogRepo: 'no-owner',
          ),
        ),
      );
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('production'));
      expect(reason, contains('controller'));
      expect(reason, contains('build plane'));
      expect(reason, contains('nobody'));
      expect(reason, contains('no-owner'));
    });

    test('a map with no alert recipient is refused here, not at the first sync', () async {
      final CheckResult answer = await writeMap.check(
        contextOn(answers: answering(alertRecipients: const <String>[])),
      );
      expect((answer as Blocked).reason, contains('alert recipient'));
    });

    test('a slave names the cluster it belongs to, and a master names none', () async {
      final CheckResult orphan = await writeMap.check(
        contextOn(
          answers: answering(domain: 's1.example.com', role: 'slave'),
        ),
      );
      expect((orphan as Blocked).reason, contains('states none'));

      final CheckResult doubled = await writeMap.check(
        contextOn(answers: answering(master: 'm0.example.com')),
      );
      expect((doubled as Blocked).reason, contains('cannot also name another one'));
    });

    test('taking it back removes a map nothing held before', () async {
      final FakeFiles files = FakeFiles();
      final StepContext context = contextOn(files: files);

      final String? before = await writeMap.capture(context);
      await writeMap.apply(context);
      await writeMap.undo(context, before);
      expect(files.contents.containsKey(mapPath), isFalse);
    });

    test('taking it back restores the map byte for byte, including what was never committed', () async {
      // What the capture read goes back, and it is read off the file rather than out of git. A map
      // an operator had edited and not committed comes back with that edit; asking git for it would
      // have handed back the committed text and thrown the edit away, in the middle of cleaning up
      // after a failure.
      const String edited = 'clusters:\n  - fqdn: m1.example.com # an operator typed this\n';
      final FakeFiles files = FakeFiles(<String, String>{mapPath: edited});
      final StepContext context = contextOn(files: files);

      final String? before = await writeMap.capture(context);
      await writeMap.apply(context);
      expect(files.contents[mapPath], isNot(edited), reason: 'the apply really did overwrite it');

      await writeMap.undo(context, before);
      expect(files.contents[mapPath], edited);
      expect(files.deleted, isEmpty);
    });
  });

  group('an installation is one stage and one role', () {
    /// Everything the trunk carries, before any of it is reduced.
    List<String> trackedFiles({String otherMap = 'clusters/active/s1.example.com.yaml'}) =>
        <String>[
          'clusters/active/$fqdn.yaml',
          otherMap,
          'registrations/acme/build.yaml',
          'registrations/example-consumer/build.yaml',
          'platform/values-dev.yaml',
          'platform/values-test.yaml',
          'platform/values-prod.yaml',
          'argocd/dev/apps/root-app.yaml',
          'argocd/test/apps/root-app.yaml',
          'argocd/prod/apps/root-app.yaml',
          'apps/web/values-dev.yaml',
          'apps/web/values-test.yaml',
          'apps/web/values-prod.yaml',
          'charts/tenant/templates/values-prod.yaml',
          'templates/values-prod.yaml',
        ];

    FakeShell listing(List<String> tracked, {String head = fqdn}) => FakeShell()
      ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$head\n')
      ..answers('git -C $repository ls-files --full-name', '${tracked.join('\n')}\n');

    FakeFiles treeOf(List<String> tracked, {String role = 'master', String stage = 'dev'}) =>
        FakeFiles(<String, String>{
          for (final String path in tracked) '$repository/$path': 'content of $path\n',
          '$repository/clusters/active/$fqdn.yaml': 'fqdn: $fqdn\nstage: $stage\nrole: $role\n',
        });

    bool has(FakeFiles files, String path) => files.contents.containsKey('$repository/$path');

    test('the two stages this installation is not are gone, and its own is untouched', () async {
      // Not tidying: with no second stage left, the stage a chart renders, the paths its secrets
      // come from and the names of its releases cannot disagree with one another.
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);
      final StepContext context = contextOn(shell: listing(tracked), files: files);

      await roleStep.apply(context);

      expect(has(files, 'platform/values-dev.yaml'), isTrue);
      expect(has(files, 'argocd/dev/apps/root-app.yaml'), isTrue);
      expect(has(files, 'apps/web/values-dev.yaml'), isTrue);
      for (final String gone in <String>[
        'platform/values-test.yaml',
        'platform/values-prod.yaml',
        'argocd/test/apps/root-app.yaml',
        'argocd/prod/apps/root-app.yaml',
        'apps/web/values-test.yaml',
        'apps/web/values-prod.yaml',
      ]) {
        expect(has(files, gone), isFalse, reason: '$gone belongs to a stage this is not');
      }
      expect(await roleStep.check(context), isA<Satisfied>());
    });

    test('product material named like a stage file survives', () async {
      // A chart's own templates are shipped to every installation and belong to none, so nothing
      // that matches by name alone may reach them.
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);

      await roleStep.apply(contextOn(shell: listing(tracked), files: files));

      expect(has(files, 'charts/tenant/templates/values-prod.yaml'), isTrue);
      expect(has(files, 'templates/values-prod.yaml'), isTrue);
    });

    test('the stage kept is the one it was told, never one read off the domain', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked, stage: 'prod');

      await roleStep.apply(
        contextOn(
          shell: listing(tracked),
          files: files,
          answers: answering(stage: 'prod'),
        ),
      );

      expect(has(files, 'platform/values-prod.yaml'), isTrue);
      expect(has(files, 'platform/values-dev.yaml'), isFalse);
    });

    test('a master keeps the books: every registration and every cluster map', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);

      await roleStep.apply(contextOn(shell: listing(tracked), files: files));

      expect(has(files, 'registrations/acme/build.yaml'), isTrue);
      expect(has(files, 'registrations/example-consumer/build.yaml'), isTrue);
      expect(has(files, 'clusters/active/s1.example.com.yaml'), isTrue);
      expect(has(files, 'clusters/active/$fqdn.yaml'), isTrue);
    });

    test('a slave keeps none of them but its own map', () async {
      // A second copy of the books on a slave is not redundant, it is harmful: it goes stale the
      // moment anything writes to the master's branch, and a stale book is worse than none.
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked, role: 'slave');
      final StepContext context = contextOn(
        shell: listing(tracked),
        files: files,
        answers: answering(role: 'slave', master: 'm0.example.com'),
      );

      await roleStep.apply(context);

      expect(has(files, 'registrations/acme/build.yaml'), isFalse);
      expect(has(files, 'registrations/example-consumer/build.yaml'), isFalse);
      expect(has(files, 'clusters/active/s1.example.com.yaml'), isFalse);
      expect(has(files, 'clusters/active/$fqdn.yaml'), isTrue);
      expect(await roleStep.check(context), isA<Satisfied>());
    });

    test('with no map on the branch nothing is decided and nothing is removed', () async {
      // Pruning the wrong way deletes an installation's registrations and every cluster map it
      // holds, so a run that cannot tell refuses instead of guessing.
      final List<String> tracked = trackedFiles();
      final FakeFiles files = FakeFiles(<String, String>{
        for (final String path in tracked)
          if (path != 'clusters/active/$fqdn.yaml') '$repository/$path': 'content\n',
      });
      final StepContext context = contextOn(shell: listing(tracked), files: files);

      final CheckResult answer = await roleStep.check(context);
      expect((answer as Blocked).reason, contains('clusters/active/$fqdn.yaml'));
      expect(files.deleted, isEmpty);
      expect(has(files, 'registrations/example-consumer/build.yaml'), isTrue);
      expect(has(files, 'platform/values-prod.yaml'), isTrue);
    });

    test('a map that disagrees with the run is refused rather than one of them chosen', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked, role: 'slave');
      final CheckResult answer = await roleStep.check(
        contextOn(shell: listing(tracked), files: files),
      );

      expect((answer as Blocked).reason, contains('slave'));
      expect(answer.reason, contains('master'));
      expect(files.deleted, isEmpty);
    });

    test('a map stating a role that is not one is refused', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked)
        ..contents['$repository/clusters/active/$fqdn.yaml'] =
            'fqdn: $fqdn\nstage: dev\nrole: controller\n';

      final CheckResult answer = await roleStep.check(
        contextOn(shell: listing(tracked), files: files),
      );
      expect((answer as Blocked).reason, contains('controller'));
    });

    test('the trunk is refused, so it goes on carrying every stage', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);
      final CheckResult answer = await roleStep.check(
        contextOn(
          shell: listing(tracked, head: trunk),
          files: files,
        ),
      );

      expect((answer as Blocked).reason, contains('cut the branch first'));
      expect(has(files, 'platform/values-prod.yaml'), isTrue);
      expect(has(files, 'platform/values-test.yaml'), isTrue);
      expect(has(files, 'platform/values-dev.yaml'), isTrue);
    });

    test('a second run has nothing to remove and removes nothing', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);
      final StepContext context = contextOn(shell: listing(tracked), files: files);

      await roleStep.apply(context);
      files.deleted.clear();

      expect(await roleStep.check(context), isA<Satisfied>());
      await roleStep.apply(context);
      expect(files.deleted, isEmpty);
    });

    test('taking it back asks git for exactly what is missing', () async {
      final List<String> tracked = trackedFiles();
      final FakeFiles files = treeOf(tracked);
      final FakeShell shell = listing(tracked);
      final StepContext context = contextOn(shell: shell, files: files);

      final List<String> removed = await roleStep.capture(context);
      await roleStep.apply(context);
      await roleStep.undo(context, removed);

      final String restore = shell.ran.firstWhere(
        (String each) => each.contains('checkout --'),
        orElse: () => '',
      );
      expect(restore, contains('platform/values-prod.yaml'));
      expect(restore, contains('argocd/test/apps/root-app.yaml'));
      expect(restore, isNot(contains('platform/values-dev.yaml')));
    });
  });
}

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
