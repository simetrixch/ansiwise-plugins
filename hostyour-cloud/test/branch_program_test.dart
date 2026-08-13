// A test may read the real files; the rule that confines `dart:io` is about the shipped library. A
// test that could not open `programs/` would be verifying a copy of the program rather than the
// program itself.
import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// The whole of `deploy-branch`, run against a checkout that exists only in memory.
///
/// It runs the real program file through the real registry, in every mode, and looks at what came
/// out — which is the only way to test the thing this program mostly is: an order.
void main() {
  // The six plugins the shipped configuration turns on, composed the way the binary composes
  // them. Resolved once, because reading a file per test says nothing more than reading it once.
  late final Registry shipped;
  setUpAll(() async => shipped = await shippedRegistry());

  const String repository = '/srv/hostyour-cloud';
  const String fqdn = 'm1.example.com';
  const String trunk = 'master';

  /// The marker the tenant generators name their catalog by, as the tree and the row write it.
  const String catalogMarker = '__CATALOG_REPO__';

  /// The one template this program names, as its row names it.
  const String mailDnsTemplate = 'ansiwise/templates/mail-dns.tpl';

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
    // The tenant generators, in the shape the tree really carries them: the member charts pinned to
    // the trunk by the keep marker, the catalog named by a marker with the forge around it, and the
    // two markers no row of this program fills.
    'argocd/dev/apps/catalog.yaml':
        'spec:\n'
        '  source:\n'
        '    targetRevision: master # set-domain:keep\n'
        '    repoURL: https://github.com/__CATALOG_REPO__.git\n'
        '    books: __BOOKS_BRANCH__\n'
        '  selector:\n'
        '    cluster: __CLUSTER__\n',
    'argocd/test/apps/root-app.yaml': 'targetRevision: master\n',
    'argocd/prod/apps/root-app.yaml': 'targetRevision: master\n',
    // A marker filled by Helm at render and by no step at all, so a scan of the branch has to find
    // it standing and not report it as unfilled work.
    'apps/consumer-build/files/applicationset.yaml':
        'revision: __BOOKS__\n'
        'targetRevision: __BRANCH__\n'
        'valueFiles: [values-__STAGE__.yaml]\n',
    // The dashboard's values, whose two markers no row of this program fills either.
    'bootstrap/kube/values.yaml':
        'settings:\n'
        '  clusterName: "__CLUSTER_NAME__"\n'
        'config:\n'
        '  inClusterContextName: "__MASTER_NAME__"\n',
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
        'BUILD_PLANE_FQDN=""\n'
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
    // Derived from the tree and not written out, exactly as the two above are: a fixture naming the
    // one file it knows about would answer the same whether or not the marker had spread, and the
    // pathspec is what the row states — a marker outside the generator tree is not in the answer,
    // because git would not return it either.
    final List<String> carryingCatalog = <String>[
      for (final MapEntry<String, String> file in tree.entries)
        if (file.key.startsWith('argocd/') && file.value.contains('__CATALOG_REPO__')) file.key,
    ];

    final FakeShell shell = FakeShell()
      // The one tool this program is, asked for at its head before anything is written. A fixture
      // not answering for it would be a machine with no git, where every run stops at the first
      // step — which is what the gate is for and not what this fixture is for.
      ..answers(onThePathKey('git'), '/usr/bin/git\n')
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
      )
      ..answers(
        'git -C $repository grep --full-name --files-with-matches --fixed-strings -e __CATALOG_REPO__ '
        '-- argocd',
        carryingCatalog.isEmpty ? '' : '${carryingCatalog.join('\n')}\n',
      );

    return (
      shell: shell,
      files: FakeFiles(<String, String>{
        for (final MapEntry<String, String> file in tree.entries)
          '$repository/${file.key}': file.value,
        // The template a row of this program names, at the path that row names it under — relative
        // to where the run was started, which is where the programs are read from too. READ OFF THE
        // DISK and never pasted in: a copy here would measure the copy, and the file that ships
        // could lose a line or gain a slot nothing fills with every assertion below still passing.
        mailDnsTemplate: File('$installationRoot/$mailDnsTemplate').readAsStringSync(),
        'ansiwise/templates/cluster-map.tpl': File('$installationRoot/ansiwise/templates/cluster-map.tpl').readAsStringSync(),
        'ansiwise/templates/config.tpl': File('$installationRoot/ansiwise/templates/config.tpl').readAsStringSync(),
        'ansiwise/templates/secrets.tpl': File('$installationRoot/ansiwise/templates/secrets.tpl').readAsStringSync(),
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
    // Sixteen: the six gates and cuts at the head — the pair of answers about the master part, the
    // domain answer, the tool, the committer identity, the push and the branch — the five that stamp
    // the branch and write its map, the three that write the files under configs and secrets named
    // for this stage, and the two that render what makes it one installation: the profile every
    // chart reads and the toggles that decide which applications run here.
    expect(deployBranch().steps, hasLength(16));
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
            // runs this program. The git steps say `base` and `branch` for the same word, because
            // the package they come from knows a branch and has never heard of a trunk.
            'repository', 'trunk', 'base', 'branch',
            // What this checkout calls its remote. git gives a clone's remote the name "origin"
            // and a checkout made another way carries whatever was chosen, so the name is stated
            // here — and it is a fact of the checkout on every machine, not of one installation.
            'remote',
            // The NAME of the answer the branch is named after, and never the answer itself. The
            // value here is the word "fqdn"; what stands under that word is this run's own domain,
            // which is read out of the run and never written into this file.
            'name_answer',
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
            // The NAME of the answer a stamp reads the value it writes out of, and the marker a line
            // of this tree carries to be left alone. The first is a question and never an answer;
            // the second is a word written into the product's own files.
            'value_answer', 'keep_marker',
            // Which parts of this tree hold product material rather than installation state. Facts
            // of the tree being generated, the same on every installation cut from it, and they
            // stand here rather than as a default in the step because a package that knows how to
            // rewrite a checkout must not decide what any one checkout keeps.
            'excluded_segments', 'excluded_names', 'script_suffixes',
            // Where a template stands, where the file it renders goes, and what may read that file.
            // All three are the shape of the product's own tree and the same on every installation
            // — the path carries a SLOT where one installation differs, and what fills the slot is
            // an answer named by `run_answer` rather than a value written here.
            'template', 'path', 'file_mode', 'run_answer', 'skippable_answers',
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
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it = await run(Mode.dry);
      final List<StepRecord> failed = it.record.steps.where((StepRecord s) => s.verdict is Failed).toList();
      for (final step in failed) {
        print('FAILED STEP: ${step.step} - ${(step.verdict as Failed).reason}');
      }
      expect(
        failed.length,
        0,
        reason:
            'what the check answers differs from every file, and none is missing, so '
            'every step says what it would write',
      );
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

    test('the catalog this installation named reaches the tenant generators', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      // READ OFF THE BRANCH, never off the row. A row naming a marker no file carries stamps
      // nothing and reports itself satisfied, so the program file says the same thing whether the
      // tree was rewritten or not. The forge and the suffix are the tree's own, and what the run
      // put between them is the answer.
      expect(
        read(it.files, 'argocd/dev/apps/catalog.yaml'),
        contains('repoURL: https://github.com/example-org/tenant-catalog.git'),
      );
    });

    test('what is left between double underscores is only what nothing fills', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(Mode.run);

      // SCANNED off the generated branch, file by file. Asking the program which markers it stamps
      // would answer exactly the same on a tree where every stamp had matched nothing, which is the
      // failure this looks for.
      final Map<String, List<String>> left = <String, List<String>>{};
      for (final MapEntry<String, String> file in it.files.contents.entries) {
        if (!file.key.startsWith('$repository/')) {
          continue;
        }
        final List<String> markers = _markersIn(file.value);
        if (markers.isNotEmpty) {
          left[file.key.substring(repository.length + 1)] = markers;
        }
      }

      expect(left, <String, List<String>>{
        // Filled by Helm at render, from global.booksBranch, global.domain and global.env. The body
        // is held outside templates/ so ArgoCD's own braces survive Helm, and the chart's wrapper
        // substitutes these three — no step is meant to touch them, and one that did would be
        // rewriting product every installation shares.
        'apps/consumer-build/files/applicationset.yaml': <String>[
          '__BOOKS__',
          '__BRANCH__',
          '__STAGE__',
        ],
        // FILLED BY NOTHING, and named here so it cannot go quiet. The books branch is this
        // cluster's own domain where it holds the master role and the named master's domain where it
        // does not; the cluster is the first DNS label of this cluster's domain, which is what the
        // Controller writes into a registration. Neither is one answer this program holds, so no row
        // of the stamp can write either: the stamp replaces a literal by the value of ONE answer,
        // and a value that has to be chosen between two answers or cut out of one is not that.
        'argocd/dev/apps/catalog.yaml': <String>['__BOOKS_BRANCH__', '__CLUSTER__'],
        // Filled by nothing for the same reason: both are a first DNS label — this cluster's, and
        // that of the cluster holding the master role.
        'bootstrap/kube/values.yaml': <String>['__CLUSTER_NAME__', '__MASTER_NAME__'],
      });
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

    test('the answer is refused before any machine is asked anything', () {
      // The one question that needs no tool at all stands ahead of the tool being looked for, so an
      // operator who typed a name that is no domain learns it without a command having run.
      expect(at('require_installation_domain'), lessThan(at('require_commands')));
    });

    test('nothing is asked of the remote before the cheap local questions', () async {
      expect(at('require_git_identity'), lessThan(at('require_pushable_remote')));
    });

    test('push ability is proven before anything changes', () {
      final ResolvedProgram program = deployBranch();
      // Built with the defaults the step declares, exactly as the engine builds it: a step relying
      // on one is refused outright by a reader that skips them, and the failure looks like a broken
      // program rather than like a test that read the row too narrowly.
      final int firstChange = program.steps.indexWhere(
        (ResolvedStep s) => s.registered.create(_withDefaults(s)) is! ObservingStep,
      );
      expect(firstChange, isNot(-1));
      expect(
        at('require_pushable_remote'),
        lessThan(firstChange),
        reason: 'a branch generated and then unpushable is the worst of both',
      );
    });

    test('all three rows of the stamp are there, and each replaces what its own job needs', () {
      // The domain row replaces what the trunk carries in place of a domain, and the rule the gate
      // measures the tree by is where that literal is written down. The revision row replaces the
      // trunk's own name under the generator tree, on the two keys that carry a branch. The catalog
      // row replaces the marker the tenant generators name their catalog by, under the same tree.
      expect(atStamp(FqdnSelection.placeholder), isNot(-1));
      expect(atStamp(trunk), isNot(-1));
      expect(atStamp(catalogMarker), isNot(-1));

      final ResolvedStep catalog = deployBranch().steps[atStamp(catalogMarker)];
      expect(catalog.argumentsWithDefaults.text('tree'), RolePruning.generatorTree);
      expect(
        catalog.argumentsWithDefaults.has('keys'),
        isFalse,
        reason:
            'the marker is a literal nothing else carries, so wherever it stands it is the value',
      );

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
      // Written as ABSENT and not as an empty value. Neither key carries a default any more, so the
      // off state of each is the key being left out — the whole checkout, and every occurrence on
      // the line being the value. A row writing them as empty would look the same on the machine
      // and would be a value this program chose where it means to choose nothing.
      expect(
        domain.argumentsWithDefaults.has('tree'),
        isFalse,
        reason: 'the placeholder stands anywhere in the checkout, not under one directory',
      );
      expect(domain.argumentsWithDefaults.has('keys'), isFalse);
    });

    test('what the run selects files by is what the gate measures the tree by', () {
      // THE GUARANTEE THAT USED TO COME FROM A DEFAULT, RESTORED AS AN ASSERTION. The three
      // exclusion lists were `defaultValue` on the step and read off the rule object, so a row
      // saying nothing could not disagree with the gate. They are stated by this program now — which
      // is where a value the product chose belongs — and nothing about the declaration keeps the two
      // in step any more. This is what does: every row of the stamp states exactly the lists the
      // rule the gate applies is built from, and a row changing one turns this red instead of
      // leaving the gate certifying a stamp it no longer describes.
      const FqdnSelection measured = StampPlaceholderInTrackedFiles.selection;
      for (final int row in <int>[
        atStamp(trunk),
        atStamp(FqdnSelection.placeholder),
        atStamp(catalogMarker),
      ]) {
        final Arguments given = deployBranch().steps[row].argumentsWithDefaults;
        expect(given.textList('excluded_segments'), measured.excludedSegments);
        expect(given.textList('excluded_names'), measured.excludedNames);
        expect(given.textList('script_suffixes'), measured.scriptSuffixes);
      }
    });

    test('every stamp names the answer its own value comes from', () {
      // The row carries the NAME of the answer and never the value, exactly as the row that cuts the
      // branch does. The two rows that write a branch name read the same answer the branch is cut
      // from, so the branch and everything pointing at it are named from one place; the catalog row
      // reads the catalog, and reading the domain there would point every tenant generator at this
      // repository instead of the one holding the member charts.
      for (final int row in <int>[atStamp(trunk), atStamp(FqdnSelection.placeholder)]) {
        expect(deployBranch().steps[row].argumentsWithDefaults.text('value_answer'), 'fqdn');
      }
      expect(
        deployBranch().steps[atStamp(catalogMarker)].argumentsWithDefaults.text('value_answer'),
        'catalog_repo',
      );
    });

    test('the branch exists before anything is stamped into it', () {
      expect(at('git_branch'), lessThan(atStamp(trunk)));
      expect(at('git_branch'), lessThan(atStamp(FqdnSelection.placeholder)));
      expect(at('git_branch'), lessThan(atStamp(catalogMarker)));
      expect(at('git_branch'), lessThan(at('stamp_role')));
    });

    test('the branch is named from the same answer every stamp below reads', () {
      // The row carries the NAME of the answer and never a value. A row naming another answer would
      // cut a branch nothing else in this program is about, and every stamp would write into it
      // under a name taken from somewhere else.
      final ResolvedStep cut = deployBranch().steps[at('git_branch')];
      expect(cut.argumentsWithDefaults.text('name_answer'), 'fqdn');
      expect(cut.argumentsWithDefaults.text('base'), trunk);
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

/// Every `__MARKER__` in [text], each named once, in alphabetical order.
///
/// Alphabetical rather than in the order they stand: what is asserted is WHICH markers a file still
/// carries, and a line somebody moved would otherwise report a difference that is not one.
List<String> _markersIn(String text) =>
    _marker.allMatches(text).map((Match found) => found.group(0)!).toSet().toList()..sort();

/// What a marker looks like in this tree: capitals between two double underscores.
final RegExp _marker = RegExp('__[A-Z][A-Z0-9_]*__');

/// The arguments [resolved] runs with: what the program wrote, plus what the step declares by
/// default.
Arguments _withDefaults(ResolvedStep resolved) {
  final Map<String, Object> defaults = <String, Object>{
    for (final ArgumentSpec spec in resolved.registered.arguments)
      if (spec.defaultValue case final Object value) spec.name: value,
  };
  return defaults.isEmpty
      ? resolved.entry.arguments
      : resolved.entry.arguments.withDefaults(defaults);
}
