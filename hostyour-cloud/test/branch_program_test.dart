// A test may read the real files; the rule that confines `dart:io` is about the shipped library. A
// test that could not open `programs/` would be verifying a copy of the program rather than the
// program itself.
import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// The whole of `deploy-branch`, run against a checkout that exists only in memory.
///
/// It runs the real program file through the real registry, in every mode, and looks at what came
/// out — which is the only way to test the thing this program mostly is: an order.
void main() {
  // The five plugins the shipped configuration turns on, composed the way the binary composes
  // them. Resolved once, because reading a file per test says nothing more than reading it once.
  late final Registry shipped;
  setUpAll(() async => shipped = await shippedRegistry());

  const String repository = '/srv/hostyour-cloud';
  const String fqdn = 'm1.example.com';
  const String trunk = 'master';

  Program declared() => loadProgram(
    File(programAt('deploy-branch.yaml')).readAsStringSync(),
    where: 'deploy-branch.yaml',
  );

  ResolvedProgram deployBranch() => ProgramResolver(shipped).resolve(declared());

  /// What an operator supplies, put through the program's OWN declaration.
  ///
  /// Validated rather than handed straight to the runner, so this fixture cannot drift from what
  /// `deploy-branch.yaml` asks for: an answer the program stopped declaring, or a required one
  /// nobody gave, fails here instead of leaving a step reading an empty bag.
  Arguments answers({String buildPlane = fqdn}) => declared().answers.validate(<String, Object?>{
    'fqdn': fqdn,
    'stage': 'dev',
    'role': 'master',
    'build_plane': buildPlane,
    'unit_apex': 'example.com',
    'platform_domain': 'example.com',
    'alert_recipients': <String>['alerts@example.com'],
    'catalog_repo': 'example-org/tenant-catalog',
    'tailnet_url': 'https://tailnet.example.com',
    'letsencrypt_email': 'certs@example.com',
    'idp_bootstrap_email': 'admin@example.com',
    'gitops_repo_pat': 'writer-credential-0001',
    'gitops_repo_read_pat': 'reader-credential-0001',
    'cloudflare_api_token': 'cloudflare-credential-0001',
    'storage_box_host': 'u000000.your-storagebox.de',
    'storage_box_user': 'u000000-sub1',
    'storage_box_password': 'storage-credential-0001',
    'registry_dockerhub_user': 'example-hub-user',
    'registry_dockerhub_token': 'dockerhub-credential-0001',
    'build_hostyour_cloud_repo_pat': 'build-credential-0001',
    'build_catalog_repo_pat': 'catalog-credential-0001',
  }, program: 'deploy-branch');

  /// What the trunk carries, before this installation is made out of it.
  Map<String, String> trunkTree() => <String, String>{
    // The nine toggles stamp_app_toggles decides, as the trunk carries them: a paragraph
    // explaining the application and one line the step owns. They are here rather than left out
    // because the ApplicationSet matches on these files — a tree without them is a tree where
    // those applications reach no cluster, which the step refuses by name.
    for (final String app in <String>[
      ...StampAppToggles.onTheBuildPlane,
      ...StampAppToggles.whereTheMasterIs,
      ...StampAppToggles.whereTheMasterIsNot,
    ])
      'cluster/apps/$app.yaml':
          '# What this application is, and when it belongs on a cluster.\nname: $app\ndeploy: "false"\n',
    'cluster/profile.yaml': 'global: {}\n',
    'platform/values-dev.yaml': 'global:\n  domain: example.invalid\n  env: dev\n',
    'platform/values-test.yaml': 'global:\n  domain: example.invalid\n  env: test\n',
    'platform/values-prod.yaml': 'global:\n  domain: example.invalid\n  env: prod\n',
    'argocd/dev/apps/root-app.yaml':
        'spec:\n'
        '  source:\n'
        '    targetRevision: &branch master # the branch this installation reads\n'
        '    host: idp.example.invalid\n',
    'argocd/dev/apps/catalog.yaml':
        'spec:\n'
        '  source:\n'
        '    targetRevision: master # set-domain:keep\n'
        '    books: __BOOKS_BRANCH__\n',
    'argocd/test/apps/root-app.yaml': 'targetRevision: master\n',
    'argocd/prod/apps/root-app.yaml': 'targetRevision: master\n',
    'apps/web/values-dev.yaml':
        'labels:\n'
        '  digitacloud.app/workload: web\n'
        'host: web.example.invalid\n',
    'apps/web/values-test.yaml': 'host: web.example.invalid\n',
    'apps/web/values-prod.yaml': 'host: web.example.invalid\n',
    'registrations/acme/build.yaml': 'name: acme\n',
    'clusters/active/$fqdn.yaml': 'fqdn: $fqdn\nstage: dev\nrole: master\nrelease: 2026.07.3\n',
    'clusters/active/s1.example.com.yaml': 'fqdn: s1.example.com\nrole: slave\n',
    // The two templates the answers become. They carry example.com and never example.invalid: an
    // illustration is a different literal from the placeholder, which is why the domain stamp
    // leaves them alone without having to recognise a domain.
    'configs/config.example':
        '# What you fill in.\n'
        'LETSENCRYPT_EMAIL="user@example.com"\n'
        'IDP_BOOTSTRAP_EMAIL="user@example.com"\n'
        'ALERT_RECIPIENTS=""\n'
        'UNIT_APEX=""\n'
        'PLATFORM_DOMAIN=""\n'
        'BUILD_PLANE=""\n'
        'CATALOG_REPO=""\n'
        '# Filled from the domain and the stage.\n'
        'CLUSTER_NAME="my-cluster"\n'
        'DOMAIN_SUFFIX="example.com"\n'
        'DEPLOY_ENV="prod"\n'
        '# A platform default, which nobody is asked for.\n'
        'POD_CIDR="10.244.0.0/16"\n',
    'secrets/secrets.example':
        '# The credentials a third party issues.\n'
        'GITOPS_REPO_PAT=""\n'
        'GITOPS_REPO_READ_PAT=""\n'
        'CLOUDFLARE_API_TOKEN=""\n'
        'STORAGE_BOX_HOST=""\n'
        'STORAGE_BOX_USER=""\n'
        'STORAGE_BOX_PASSWORD=""\n'
        'REGISTRY_DOCKERHUB_USER=""\n'
        'REGISTRY_DOCKERHUB_TOKEN=""\n'
        'BUILD_HOSTYOUR_CLOUD_REPO_PAT=""\n'
        'BUILD_CATALOG_REPO_PAT=""\n'
        '# Written back once this installation is running.\n'
        'VAULT_ROOT_TOKEN=""\n',
    'branch-classes.yaml': 'never-stamp:\n  - docs/ quotes example.invalid to explain this\n',
    'docs/branching.md': 'The trunk carries example.invalid until a branch is cut.\n',
    'templates/values.yaml': 'host: example.invalid\n',
    'install.sh':
        '#!/usr/bin/env bash\n[[ "\$FQDN" == "example.invalid" ]] && die "give a domain"\n',
    'tools/ops/sync-versions': '#!/usr/bin/env bash\necho example.invalid\n',
    'tools/ops/publish.ps1': 'param([string]\$Domain = "example.invalid")\n',
  };

  /// The checkout, already on the installation branch — the run that re-stamps after a merge from
  /// the trunk, which is the shape every mode can be exercised against.
  ({FakeShell shell, FakeFiles files}) checkout() {
    final Map<String, String> tree = trunkTree();
    final List<String> carryingTrunk = <String>[
      'argocd/dev/apps/root-app.yaml',
      'argocd/dev/apps/catalog.yaml',
      'argocd/test/apps/root-app.yaml',
      'argocd/prod/apps/root-app.yaml',
    ];
    final List<String> carryingPlaceholder = <String>[
      for (final MapEntry<String, String> file in tree.entries)
        if (file.value.contains('example.invalid')) file.key,
    ];

    final FakeShell shell = FakeShell()
      // The one tool this program is, asked for at its head before anything is written. A fixture
      // not answering for it would be a machine with no git, where every run stops at the first
      // step — which is what the gate is for and not what this fixture is for.
      ..answers('command -v git', '/usr/bin/git\n')
      ..answers('git -C $repository rev-parse --git-dir', '.git\n')
      ..answers('git -C $repository config --get user.name', 'Example Operator\n')
      ..answers('git -C $repository config --get user.email', 'operator@example.com\n')
      ..answers('git -C $repository remote get-url origin', 'git@example.com:example/cloud.git\n')
      ..answers('git -C $repository ls-remote --heads origin', 'abc\trefs/heads/master\n')
      ..answers('git -C $repository push --dry-run origin $trunk', '')
      ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$fqdn\n')
      ..answers('git -C $repository status --porcelain', '')
      ..answers('git -C $repository ls-files --full-name', '${tree.keys.join('\n')}\n')
      ..answers(
        'git -C $repository grep --full-name --files-with-matches --fixed-strings -e $trunk '
            '-- argocd',
        '${carryingTrunk.join('\n')}\n',
      )
      ..answers(
        'git -C $repository grep --full-name --files-with-matches --fixed-strings -e example.invalid',
        '${carryingPlaceholder.join('\n')}\n',
      );

    return (
      shell: shell,
      files: FakeFiles(<String, String>{
        for (final MapEntry<String, String> file in tree.entries)
          '$repository/${file.key}': file.value,
      }),
    );
  }

  RunRecord header(Mode mode, FakeClock clock) => RunRecord(
    id: const RunId('20260807T120000Z-1'),
    program: const ProgramName('deploy-branch'),
    mode: mode,
    argv: const <String>['ansiwise', 'deploy-branch'],
    start: clock.now(),
    stage: const Stage('dev'),
    role: const Role('master'),
    fqdn: const Fqdn(fqdn),
    commit: 'abc1234',
    fingerprint: 'f',
  );

  Future<({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder})> run(
    Mode mode, {
    ({FakeShell shell, FakeFiles files})? on,
  }) async {
    final ({FakeShell shell, FakeFiles files}) tree = on ?? checkout();
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final RunRecord record = await Runner(
      machine: Machine(
        shell: tree.shell,
        files: tree.files,
        http: FakeHttp(),
        clock: clock,
        entropy: FakeEntropy(),
      ),
      recorder: recorder,
      redactor: Redactor.none,
    ).run(program: deployBranch(), mode: mode, header: header(mode, clock), answers: answers());
    return (record: record, shell: tree.shell, files: tree.files, recorder: recorder);
  }

  String read(FakeFiles files, String path) => files.contents['$repository/$path'] ?? '';
  bool has(FakeFiles files, String path) => files.contents.containsKey('$repository/$path');

  test('the program resolves against the registry', () {
    // Twelve: the seven that cut and stamp the branch, the three that write the files under
    // configs and secrets named for this stage, and the two that render what makes it one
    // installation — the profile every chart reads and the toggles that decide which applications
    // run here.
    expect(deployBranch().steps, hasLength(13));
  });

  test('every value an installation states about itself is an answer, not an argument', () {
    // The defect this replaces: fqdn, unit_apex, alert_recipients and the rest stood in this file
    // as step arguments with an illustration for a value, so every installation shipped with
    // somebody else's example baked into it.
    final List<String> declaredAnswers = <String>[
      for (final ArgumentSpec spec in declared().answers.specs) spec.name,
    ];
    expect(
      declaredAnswers,
      containsAll(<String>[
        'fqdn',
        'stage',
        'role',
        'unit_apex',
        'alert_recipients',
        'catalog_repo',
      ]),
    );

    for (final ResolvedStep step in deployBranch().steps) {
      expect(
        step.entry.arguments.names,
        everyElement(
          isIn(<String>[
            // Where the checkout is and what the trunk is called: the same on every machine that
            // runs this program.
            'repository', 'trunk',
            // The stages the PRODUCT carries, of which an installation is exactly one, and the
            // commands the program assumes. Both are facts about the product.
            'stages', 'commands',
            // What the trunk writes where an installation writes its own: the trunk's own name, and
            // the placeholder domain. Neither names an installation — they are what an installation
            // REPLACES, which is why they can stand in a file that ships to all of them.
            'placeholder',
            // Which part of the tree a stamp is confined to, and the keys it rewrites there. Both
            // are the shape of the product's own files.
            'tree', 'keys',
          ]),
        ),
        reason:
            '${step.entry.step} is given something in the program file that names one '
            'installation, and a program file ships to every installation',
      );
    }
  });

  test('every secret is declared as one, and no secret carries a default', () {
    // A default for a secret is a credential written into a file that ships to every installation.
    for (final ArgumentSpec spec in declared().answers.specs) {
      if (spec.secret) {
        expect(spec.hasDefault, isFalse, reason: '${spec.name} is secret and carries a default');
      }
    }
    expect(
      declared().answers.secretNames,
      containsAll(<String>[
        'gitops_repo_pat',
        'gitops_repo_read_pat',
        'cloudflare_api_token',
        'storage_box_password',
      ]),
    );
  });

  test('every answer says what it is for, to somebody who has never seen this system', () {
    for (final ArgumentSpec spec in declared().answers.specs) {
      expect(
        spec.describes.length,
        greaterThan(40),
        reason: '${spec.name} shows a bare field name to whoever fills the form in',
      );
    }
  });

  group('--mode dry', () {
    test('changes nothing at all', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a dry run may only run commands a step declared as observing',
      );
    });

    test('every step comes back green', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      expect(it.record.exitCode, 0);
      for (final StepRecord step in it.record.steps) {
        expect(step.verdict, isA<Succeeded>(), reason: '${step.step} was not green');
      }
    });

    test('it says which files it would rewrite and which it would remove', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.dry);

      // Two different places, and the difference is which of them carries the PATHS.
      //
      // The domain stamp's plan is a diff of the LINES that change, so the file each line belongs to
      // is only in what the step says — which is why that line is at info and stays in a normal run.
      // The role stamp's plan is the list of removed paths itself, so the same fact is in the plan
      // and its per-path line is working-out that a debugging run asks for.
      expect(it.recorder.logLines, contains(contains('platform/values-dev.yaml would have')));

      final StepRecord role = it.record.steps.firstWhere(
        (StepRecord step) => step.step == const StepName('stamp_role'),
      );
      final DiffPlan removed = role.plan! as DiffPlan;
      expect(removed.before, contains('platform/values-prod.yaml'));
      expect(removed.before, contains('argocd/test/apps/root-app.yaml'));
      expect(removed.after, isEmpty, reason: 'what it plans is that these are no longer there');
    });
  });

  group('--mode test', () {
    test('it measures and stops there', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.test);

      expect(it.record.exitCode, 0);
      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(it.shell.ran, contains('git -C $repository push --dry-run origin $trunk'));
    });
  });

  group('--mode run', () {
    test('every step comes back green', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(it.record.exitCode, 0);
      for (final StepRecord step in it.record.steps) {
        expect(step.verdict, isA<Succeeded>(), reason: '${step.step} was not green');
      }
    });

    test('the branch reads its own name everywhere an installation says one', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(read(it.files, 'platform/values-dev.yaml'), contains('domain: $fqdn'));
      expect(
        read(it.files, 'argocd/dev/apps/root-app.yaml'),
        contains('targetRevision: &branch $fqdn'),
      );
      expect(read(it.files, 'argocd/dev/apps/root-app.yaml'), contains('host: idp.$fqdn'));
    });

    test('what must survive a stamp survives it', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(read(it.files, 'argocd/dev/apps/catalog.yaml'), contains('master # set-domain:keep'));
      expect(read(it.files, 'argocd/dev/apps/catalog.yaml'), contains('books: __BOOKS_BRANCH__'));
      expect(read(it.files, 'apps/web/values-dev.yaml'), contains('digitacloud.app/workload: web'));
      expect(read(it.files, 'install.sh'), contains('example.invalid'));
      expect(read(it.files, 'tools/ops/sync-versions'), contains('example.invalid'));
      expect(read(it.files, 'tools/ops/publish.ps1'), contains('example.invalid'));
      expect(read(it.files, 'branch-classes.yaml'), contains('example.invalid'));
      expect(read(it.files, 'docs/branching.md'), contains('example.invalid'));
      expect(read(it.files, 'templates/values.yaml'), contains('example.invalid'));
    });

    test('it ends as one stage, with its books and its release pin', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      expect(has(it.files, 'platform/values-dev.yaml'), isTrue);
      expect(has(it.files, 'platform/values-test.yaml'), isFalse);
      expect(has(it.files, 'platform/values-prod.yaml'), isFalse);
      expect(has(it.files, 'argocd/test/apps/root-app.yaml'), isFalse);
      expect(has(it.files, 'apps/web/values-prod.yaml'), isFalse);

      expect(has(it.files, 'registrations/acme/build.yaml'), isTrue);
      expect(has(it.files, 'clusters/active/s1.example.com.yaml'), isTrue);
      expect(read(it.files, 'clusters/active/$fqdn.yaml'), contains('release: 2026.07.3'));
      expect(read(it.files, 'clusters/active/$fqdn.yaml'), contains('build-plane: $fqdn'));
    });

    test('the answers become the config file the rest of the installation reads', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);
      final String config = read(it.files, 'configs/config.dev');

      expect(config, contains('LETSENCRYPT_EMAIL="certs@example.com"'));
      expect(config, contains('IDP_BOOTSTRAP_EMAIL="admin@example.com"'));
      expect(config, contains('ALERT_RECIPIENTS="alerts@example.com"'));
      expect(config, contains('CATALOG_REPO="example-org/tenant-catalog"'));
      // The three the domain and the stage fully determine, written out rather than derived later.
      expect(config, contains('DEPLOY_ENV="dev"'));
      expect(config, contains('DOMAIN_SUFFIX="$fqdn"'));
      expect(config, contains('CLUSTER_NAME="$fqdn"'));
      // Everything the template holds that nobody was asked for is copied through untouched, which
      // is what keeps the paragraph of explanation above each key.
      expect(config, contains('POD_CIDR="10.244.0.0/16"'));
      expect(config, contains('# What you fill in.'));
      expect(config, isNot(contains('user@example.com')));
    });

    test('the answers become the credentials file, and it carries them exactly once', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);
      final String secrets = read(it.files, 'secrets/secrets.dev');

      expect(secrets, contains('GITOPS_REPO_PAT="writer-credential-0001"'));
      expect(secrets, contains('GITOPS_REPO_READ_PAT="reader-credential-0001"'));
      expect(secrets, contains('CLOUDFLARE_API_TOKEN="cloudflare-credential-0001"'));
      expect(secrets, contains('STORAGE_BOX_USER="u000000-sub1"'));
      // Appending produced a file carrying the same variable twice, the second one blank, and the
      // value that lost was the one somebody typed.
      expect(
        'GITOPS_REPO_PAT='.allMatches(secrets),
        hasLength(1),
        reason: 'the key is filled at its own position in the template, not appended',
      );
      // This cluster carries the build plane, so the four of the registry and the release apply.
      expect(secrets, contains('BUILD_CATALOG_REPO_PAT="catalog-credential-0001"'));
      // A key nobody was asked for is left for the phase that writes it back.
      expect(secrets, contains('VAULT_ROOT_TOKEN=""'));
    });

    test('no credential reaches the record, not even as the length of one', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      // The record is written to a file an operator reads without elevated rights, and it is
      // exported and pasted into messages when something has gone wrong.
      for (final String note in it.recorder.logLines) {
        expect(note, isNot(contains('writer-credential-0001')));
        expect(note, isNot(contains('cloudflare-credential-0001')));
      }
      for (final StepRecord step in it.record.steps) {
        if (step.plan case final DiffPlan diff) {
          expect(diff.after, isNot(contains('writer-credential-0001')));
        }
      }
    });

    test('a second run over the same tree does nothing and changes nothing', () async {
      final ({FakeShell shell, FakeFiles files}) tree = checkout();
      await run(Mode.run, on: tree);
      final Map<String, String> after = Map<String, String>.of(tree.files.contents);
      tree.files.written.clear();
      tree.files.deleted.clear();

      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) again =
          await run(Mode.run, on: tree);

      expect(again.record.exitCode, 0);
      expect(again.files.written, isEmpty);
      expect(again.files.deleted, isEmpty);
      expect(again.files.contents, after);
    });

    test('a remote that would refuse the push stops the run before any of the work', () async {
      final ({FakeShell shell, FakeFiles files}) tree = checkout();
      tree.shell.fails(
        'git -C $repository push --dry-run origin $trunk',
        stderr: 'remote: Permission denied',
      );

      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run, on: tree);

      expect(it.record.exitCode, 1);
      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(read(it.files, 'platform/values-dev.yaml'), contains('example.invalid'));
    });

    test('the trunk is left exactly as it was', () async {
      // Nothing may reach the tree every other installation is cut from. Every stamp refuses while
      // it is checked out, and the run ends without a single write.
      final ({FakeShell shell, FakeFiles files}) tree = checkout();
      tree.shell.answers('git -C $repository rev-parse --abbrev-ref HEAD', '$trunk\n');
      tree.shell.fails('git -C $repository rev-parse --verify --quiet refs/heads/$fqdn');

      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run, on: tree);

      expect(it.record.exitCode, 1);
      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(read(it.files, 'platform/values-dev.yaml'), contains('example.invalid'));
      expect(has(it.files, 'platform/values-prod.yaml'), isTrue);
      expect(
        it.record.steps.last.verdict,
        isA<Failed>(),
        reason: 'the branch was not cut, so nothing that stamps may run',
      );
    });
  });

  group('the order is the safety property', () {
    List<StepName> order() => <StepName>[
      for (final ResolvedStep step in deployBranch().steps) step.entry.step,
    ];

    int at(String name) => order().indexOf(StepName(name));

    /// Where the row of the stamp that replaces [placeholder] stands.
    ///
    /// One step, two rows, so a step name alone finds whichever comes first. What tells them apart
    /// is the literal each replaces, which is also the only difference the order turns on.
    int atStamp(String placeholder) => deployBranch().steps.indexWhere(
      (ResolvedStep step) =>
          step.entry.step == const StepName('stamp_placeholder_in_tracked_files') &&
          step.argumentsWithDefaults.text('placeholder') == placeholder,
    );

    test('nothing is asked of the remote before the cheap local questions', () async {
      expect(at('require_git_identity'), lessThan(at('require_pushable_origin')));
    });

    test('push ability is proven before anything changes', () {
      final ResolvedProgram program = deployBranch();
      final int firstChange = program.steps.indexWhere(
        (ResolvedStep s) => s.registered.create(s.entry.arguments) is! ObservingStep,
      );
      expect(firstChange, isNot(-1));
      expect(
        at('require_pushable_origin'),
        lessThan(firstChange),
        reason: 'a branch generated and then unpushable is the worst of both',
      );
    });

    test('both rows of the stamp are there, and each replaces what its half needs', () {
      // The domain row replaces what the trunk carries in place of a domain, and the rule the gate
      // measures the tree by is where that literal is written down. The revision row replaces the
      // trunk's own name under the generator tree, on the two keys that carry a branch.
      expect(atStamp(FqdnSelection.placeholder), isNot(-1));
      expect(atStamp(trunk), isNot(-1));

      final ResolvedStep revision = deployBranch().steps[atStamp(trunk)];
      expect(revision.argumentsWithDefaults.text('tree'), RolePruning.generatorTree);
      expect(revision.argumentsWithDefaults.textList('keys'), <String>[
        'revision',
        'targetRevision',
      ]);
      expect(
        revision.argumentsWithDefaults.text('trunk'),
        trunk,
        reason: 'the literal this row replaces IS the trunk, and the two have to be the same word',
      );

      final ResolvedStep domain = deployBranch().steps[atStamp(FqdnSelection.placeholder)];
      expect(
        domain.argumentsWithDefaults.text('tree'),
        '',
        reason: 'the placeholder stands anywhere in the checkout, not under one directory',
      );
      expect(domain.argumentsWithDefaults.textList('keys'), isEmpty);
    });

    test('the branch exists before anything is stamped into it', () {
      expect(at('create_install_branch'), lessThan(atStamp(trunk)));
      expect(at('create_install_branch'), lessThan(atStamp(FqdnSelection.placeholder)));
      expect(at('create_install_branch'), lessThan(at('stamp_role')));
    });

    test('the map is written after the branch is stamped and before the role reads it', () {
      // Both stamps, not one: the map names the branch of every cluster of this installation, and a
      // map written between them would hold a tree that is half retargeted and half not.
      expect(atStamp(trunk), lessThan(at('write_cluster_map')));
      expect(atStamp(FqdnSelection.placeholder), lessThan(at('write_cluster_map')));
      expect(
        at('write_cluster_map'),
        lessThan(at('stamp_role')),
        reason: 'the map is the only input the role stage has',
      );
    });
  });
}
