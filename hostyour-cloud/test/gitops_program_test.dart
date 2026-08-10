// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// The whole of `deploy-gitops`, read as the operator's own file and run against a machine that
/// exists only in memory.
///
/// The two properties this file is about are the ones a reader of the program cannot check by
/// eye: that the counts of policies and roles are exactly what the platform is specified to have,
/// and that a phase switched off leaves nothing at all behind.
void main() {
  // The five plugins the shipped configuration turns on, composed the way the binary composes
  // them. Resolved once, because reading a file per test says nothing more than reading it once.
  late final Registry shipped;
  setUpAll(() async => shipped = await shippedRegistry());

  ResolvedProgram deployGitops() => ProgramResolver(shipped).resolve(
    loadProgram(
      File(programAt('deploy-gitops.yaml')).readAsStringSync(),
      where: 'deploy-gitops.yaml',
    ),
  );

  Program program() => loadProgram(
    File(programAt('deploy-gitops.yaml')).readAsStringSync(),
    where: 'deploy-gitops.yaml',
  );

  /// What an operator supplies, put through the program's OWN declaration.
  ///
  /// Validated rather than handed straight to the runner, so this fixture cannot drift from what
  /// `deploy-gitops.yaml` asks for: an answer the program stopped declaring, or a required one
  /// nobody gave, fails here instead of leaving a step reading an empty bag.
  Arguments answered() => program().answers.validate(<String, Object?>{
    'fqdn': 'm1.example.com',
    'stage': 'dev',
    'role': 'master',
    'master': '',
  }, program: 'deploy-gitops');

  /// The value one entry gives an argument, for every entry naming [step].
  List<String> valuesOf(String step, String argument) => <String>[
    for (final ProgramStep entry in program().steps)
      if (entry.step == StepName(step))
        if (entry.arguments.optionalText(argument) case final String value) value,
  ];

  /// The grants [entry] gives a policy, as the program file writes them.
  ///
  /// Read straight out of the file and not composed: every grant carries the whole path it applies
  /// to, with `$stagePlaceholder` where one stage's tree begins, so what a caller may do is on the
  /// line rather than on the other side of a transformation.
  String grantsOf(ProgramStep entry) => entry.arguments.text('rules');

  /// A machine carrying a stage config that says [config], and nothing else.
  ({FakeShell shell, FakeFiles files, FakeHttp http}) machineWith(String config) => (
    shell: gitopsToolsPresent(),
    files: FakeFiles(<String, String>{'/srv/hostyour-cloud/configs/config.dev': config}),
    http: FakeHttp(),
  );

  Future<({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder})> run(
    String config, {
    Mode mode = Mode.run,
  }) async {
    final ({FakeShell shell, FakeFiles files, FakeHttp http}) machine = machineWith(config);
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final RunRecord record =
        await Runner(
          machine: Machine(
            shell: machine.shell,
            files: machine.files,
            http: machine.http,
            clock: clock,
            entropy: FakeEntropy(),
          ),
          recorder: recorder,
          redactor: Redactor.none,
        ).run(
          program: deployGitops(),
          mode: mode,
          header: RunRecord(
            id: const RunId('20260807T120000Z-1'),
            program: const ProgramName('deploy-gitops'),
            mode: mode,
            argv: const <String>['ansiwise', 'deploy-gitops'],
            start: clock.now(),
            stage: const Stage('dev'),
            role: const Role('master'),
            fqdn: const Fqdn('m1.example.com'),
            commit: 'abc1234',
            fingerprint: 'f',
          ),
          answers: answered(),
        );
    return (record: record, shell: machine.shell, files: machine.files, recorder: recorder);
  }

  test('the program resolves against the registry', () {
    expect(deployGitops().steps, isNotEmpty);
  });

  test('every value this installation states about itself is an answer, not an argument', () {
    // The defect this replaces: Vault's address, its credential file, the stage and this cluster's
    // own short name stood in this file as step arguments with one installation's value for each.
    // A program file ships inside the binary to every installation and nothing rewrites it, so this
    // cluster would have written its policies under another cluster's name, read the seed of
    // another stage, and pointed the browser login at somebody else's Vault.
    //
    // The names are listed rather than allow-listed the other way round: this file carries argument
    // names that ARE the platform's own decisions — the chart versions, the mount, the manifest
    // trunk, the namespaces — and a list of those would go stale on every step added.
    //
    // `url` is not among them, and it is the one name that could not be: it was what every Vault
    // step was given its address under, and it is also what a chart repository is given its address
    // under, which is the platform's. The test below catches a Vault address by its value instead.
    const List<String> namesOneInstallationOwns = <String>[
      'credentials_path',
      'secrets_path',
      'issuer_url',
      'stage',
      'fqdn',
      'domain',
      'domain_suffix',
      'cluster_name',
      'master',
    ];

    expect(<String>[
      for (final ArgumentSpec spec in program().answers.specs) spec.name,
    ], containsAll(<String>['fqdn', 'stage', 'role', 'master']));

    for (final ProgramStep entry in program().steps) {
      for (final String name in entry.arguments.names) {
        expect(
          namesOneInstallationOwns,
          isNot(contains(name)),
          reason:
              '${entry.step} is given "$name" in the program file, and that names one installation '
              '— it belongs in the answers block at the end of the file, or in cluster/profile.yaml '
              'where the branch stamp writes it',
        );
      }
    }
  });

  test('no short name, no stage and no domain is left in any argument VALUE', () {
    // The other half, and the one the list of names cannot reach: "name", "mount", "role" and
    // "body" are argument names the platform decides, and one installation's value inside them —
    // `m1-eso`, `kubernetes-m1`, `tenant-eso-dev` — reads exactly like a platform decision. What
    // this asserts is that every such value is written as the marked slot the step fills from the
    // run, so a value that ships is a value that is the same on every installation.
    final Arguments answered = program().answers.validate(<String, Object?>{
      'fqdn': 'm1.example.com',
      'stage': 'dev',
      'role': 'master',
      'master': '',
    }, program: 'deploy-gitops');
    final List<String> ofOneInstallation = <String>[
      'm1',
      answered.text('fqdn'),
      answered.text('stage'),
    ];

    for (final ProgramStep entry in program().steps) {
      for (final String name in entry.arguments.names) {
        final Object? value = entry.arguments.raw(name);
        if (value is! String) {
          continue;
        }
        for (final String own in ofOneInstallation) {
          expect(
            value,
            isNot(contains(own)),
            reason:
                '${entry.step} is given "$name: $value", and "$own" in it is one installation\'s — '
                'write $clusterPlaceholder, $stagePlaceholder, $vaultUrlPlaceholder or '
                '$kubernetesMountPlaceholder there and the step fills it in from the run',
          );
        }
      }
    }
  });

  test('a slave never arrives here', () {
    expect(program().appliesTo(const Role('master')), isTrue);
    expect(
      program().appliesTo(const Role('slave')),
      isFalse,
      reason: 'the handoff of a slave is the master\'s job, through the master\'s own reconciler',
    );
  });

  group('the counts are exact', () {
    test('eight policies on the build plane, six off it', () {
      // The count is the point, and it is the count of NAMES: the cluster manager's policy is
      // written in two shapes and only one of them ever runs, so it is one policy either way.
      final Set<String> everywhere = <String>{};
      final Set<String> onTheBuildPlane = <String>{};
      for (final ProgramStep entry in program().steps) {
        if (entry.step != const StepName('vault_policy')) {
          continue;
        }
        final String name = entry.arguments.text('name');
        if (entry.when.contains(const PredicateName('build_plane_here'))) {
          onTheBuildPlane.add(name);
        } else {
          everywhere.add(name);
        }
      }

      expect(everywhere.union(onTheBuildPlane), hasLength(8));
      expect(everywhere, hasLength(6));
      expect(
        onTheBuildPlane.difference(everywhere),
        <String>{'$clusterPlaceholder-deploy-pat-read', '$clusterPlaceholder-build-read'},
        reason: 'a build is stage-free, so its tier lives on exactly one cluster',
      );
      expect(everywhere, containsAll(<String>['admin', 'controller', 'controller-host']));
    });

    test('seven auth roles on the build plane, six off it', () {
      final Set<String> everywhere = <String>{};
      final Set<String> onTheBuildPlane = <String>{};
      for (final ProgramStep entry in program().steps) {
        if (entry.step != const StepName('vault_auth_role')) {
          continue;
        }
        final String name = entry.arguments.text('role');
        if (entry.when.contains(const PredicateName('build_plane_here'))) {
          onTheBuildPlane.add(name);
        } else {
          everywhere.add(name);
        }
      }

      expect(everywhere.union(onTheBuildPlane), hasLength(7));
      expect(everywhere, hasLength(6));
      expect(onTheBuildPlane.difference(everywhere), <String>{'build-eso'});
      expect(
        everywhere,
        containsAll(<String>[
          'default',
          'external-secrets',
          'consumer-eso',
          'tenant-eso-$stagePlaceholder',
          'controller',
          'controller-host',
        ]),
      );
    });

    test('two auth mounts and no more', () {
      // Which two, and not in which order. The mount a browser logs in through is enabled after the
      // identity provider exists, and the one workloads log in through before it — so the order
      // these appear in follows the dependency chain rather than a decision anybody made, and
      // asserting it here would make a correct reordering read as a defect.
      expect(valuesOf('vault_auth_method', 'path'), hasLength(2));
      expect(
        valuesOf('vault_auth_method', 'path'),
        containsAll(<String>['oidc', kubernetesMountPlaceholder]),
      );
    });

    test('the reader role keeps the name every rendered secret store writes', () {
      // The chart that renders a secret store per cluster re-points only the mount path and the key
      // path, and takes this name from its own default.
      expect(valuesOf('vault_auth_role', 'role'), contains('external-secrets'));
    });
  });

  group('what the cluster manager may do', () {
    /// The grants of the policy named [name] under the conditions [when].
    String policy(String name, {String? when}) => grantsOf(
      program().steps.firstWhere(
        (ProgramStep entry) =>
            entry.step == const StepName('vault_policy') &&
            entry.arguments.text('name') == name &&
            (when == null || entry.when.contains(PredicateName(when))),
      ),
    );

    test('it may write a consumer and a tenant leaf and may never read one', () {
      final String rules = policy('controller', when: 'build_plane_elsewhere');
      for (final String leaf in <String>[
        'secret/data/$stagePlaceholder/consumer/+/app',
        'secret/data/$stagePlaceholder/consumer/+/postgres',
        'secret/data/$stagePlaceholder/consumer/+/mongodb',
        'secret/data/$stagePlaceholder/tenants/+',
      ]) {
        final String line = rules
            .split('\n')
            .firstWhere((String each) => each.contains('"$leaf"'), orElse: () => '');
        expect(line, isNotEmpty, reason: '$leaf is not granted at all');
        expect(line, contains('"create"'));
        expect(line, contains('"update"'));
        expect(
          line,
          isNot(contains('"read"')),
          reason:
              'a read grant here would make the create-only write a read-before-write, and a '
              're-onboarding would then rotate the keys of something already running',
        );
      }
    });

    test('the delete it holds is on the metadata, and it is a delete alone', () {
      final String rules = policy('controller', when: 'build_plane_elsewhere');
      for (final String leaf in <String>[
        'secret/metadata/$stagePlaceholder/consumer/+/app',
        'secret/metadata/$stagePlaceholder/tenants/+',
      ]) {
        final String line = rules
            .split('\n')
            .firstWhere((String each) => each.contains('"$leaf"'), orElse: () => '');
        expect(line, contains('"delete"'));
        expect(
          line,
          isNot(contains('"create"')),
          reason: 'create on the metadata is what sets the field that makes values expire silently',
        );
        expect(line, isNot(contains('"update"')));
        expect(line, isNot(contains('"read"')));
      }
    });

    test('the build tier is granted only where the build plane runs', () {
      expect(policy('controller', when: 'build_plane_here'), contains('secret/data/build/+'));
      expect(
        policy('controller', when: 'build_plane_elsewhere'),
        isNot(contains('secret/data/build/')),
      );
    });
  });

  test('the platform reader reaches the application tier and never the system tier', () {
    final String rules = grantsOf(
      program().steps.firstWhere(
        (ProgramStep entry) =>
            entry.step == const StepName('vault_policy') &&
            entry.arguments.text('name') == '$clusterPlaceholder-eso',
      ),
    );
    expect(rules, contains('secret/data/$stagePlaceholder/app/*'));
    expect(
      rules,
      isNot(contains('system')),
      reason: 'the system tier holds the root token and the unseal keys',
    );
  });

  test('the handoff is the last step and it carries a verdict of its own', () async {
    final List<StepName> order = <StepName>[
      for (final ResolvedStep step in deployGitops().steps) step.entry.step,
    ];
    expect(order.last, const StepName('argocd_root_app'));

    final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
        await run('ENABLE_ARGOCD=true\n');
    final StepRecord handoff = it.record.steps.firstWhere(
      (StepRecord step) => step.step == const StepName('argocd_root_app'),
    );
    expect(
      handoff.verdict,
      isNot(isA<Skipped>()),
      reason: 'the handoff is a recorded step and not the absence of an error',
    );
  });

  group('the manifest the handoff applies', () {
    StepContext handoffContext(FakeFiles files) {
      final FakeClock clock = FakeClock();
      const StepName name = StepName('argocd_root_app');
      return StepContext(
        shell: FakeShell(),
        files: files,
        http: FakeHttp(),
        clock: clock,
        entropy: FakeEntropy(),
        log: RecordingLogger(recorder: MemoryRecorder(clock), redactor: Redactor.none, step: name),
        step: name,
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'stage': 'dev'}),
        facts: Facts.none,
      );
    }

    test('is a row value with the stage in a marked slot, filled from the answers', () {
      // The path is the row's to say; what the row cannot say is which stage this installation
      // runs, so that one value stands as a slot and the run fills it.
      const ArgocdRootApp handoff = ArgocdRootApp(
        repository: '/srv/hostyour-cloud',
        trunk: 'master',
      );
      expect(handoff.manifest, ArgocdRootApp.defaultManifest);
      expect(
        handoff.manifestIn(handoffContext(FakeFiles())),
        '/srv/hostyour-cloud/argocd/dev/root-app.yaml',
      );
    });

    test('a manifest row carrying a slot nothing fills is refused, not looked for', () async {
      // A misspelled slot would otherwise be looked for on disk in angle brackets, and the refusal
      // would say the branch lost a manifest nobody ever named.
      const ArgocdRootApp misspelled = ArgocdRootApp(
        repository: '/srv/hostyour-cloud',
        trunk: 'master',
        manifest: 'argocd/<stag>/root-app.yaml',
      );
      final CheckResult answer = await misspelled.check(handoffContext(FakeFiles()));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('<stag>'));
    });

    test('a branch that lost the manifest is refused with the repair', () async {
      const ArgocdRootApp handoff = ArgocdRootApp(
        repository: '/srv/hostyour-cloud',
        trunk: 'master',
      );
      final CheckResult answer = await handoff.check(handoffContext(FakeFiles()));
      expect(answer, isA<Blocked>());
      expect(
        (answer as Blocked).reason,
        contains('git -C /srv/hostyour-cloud merge master'),
        reason: 'the operator needs the command that puts it back, not a missing-file message',
      );
    });
  });

  group('an enabled gate that is off', () {
    test('leaves nothing at all behind', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run('ENABLE_VAULT=false\nENABLE_IDP=false\nENABLE_ARGOCD=false\n');

      expect(it.record.exitCode, 0, reason: 'a component nobody asked for must not fail a run');
      for (final StepRecord step in it.record.steps) {
        // The head gate is not under a condition and does not skip: it asks whether helm and
        // kubectl are there, whatever this run turns out to have to do. What it must not do is
        // change anything, and the assertions below are what hold it to that.
        if (step.step == const StepName('require_commands')) {
          continue;
        }
        expect(step.verdict, isA<Skipped>(), reason: '${step.step} was not skipped');
      }
      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'no namespace, no release, not half of one',
      );
    });

    test('the plan names the condition that skipped each row', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run('ENABLE_VAULT=false\nENABLE_IDP=false\nENABLE_ARGOCD=false\n');

      final Set<String> reasons = <String>{
        for (final StepRecord step in it.record.steps)
          if (step.verdict case final Skipped skipped) skipped.predicate,
      };
      expect(reasons, <String>{'idp_enabled', 'argocd_enabled', 'vault_enabled'});

      final List<PredicateEvaluated> measured = it.recorder.only<PredicateEvaluated>();
      expect(
        measured.map((PredicateEvaluated e) => e.because).join('\n'),
        contains('/srv/hostyour-cloud/configs/config.dev'),
        reason: 'a condition an operator cannot open is a condition they cannot act on',
      );
    });

    test('the secret store has to be asked for and the identity provider does not', () async {
      // The two defaults differ, deliberately: minting a quorum is not something a cluster gets
      // because nobody said otherwise, and a cluster without an identity provider stands.
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run('DOMAIN_SUFFIX=m1.example.com\n');

      final Map<PredicateName, bool> held = <PredicateName, bool>{
        for (final PredicateEvaluated e in it.recorder.only<PredicateEvaluated>())
          e.predicate: e.held,
      };
      expect(held[const PredicateName('idp_enabled')], isTrue);
      expect(held[const PredicateName('vault_enabled')], isFalse);
      expect(held[const PredicateName('argocd_enabled')], isFalse);
    });

    test('a checkout with no stage config decides nothing and does nothing', () async {
      final FakeClock clock = FakeClock();
      final MemoryRecorder recorder = MemoryRecorder(clock);
      final FakeShell shell = gitopsToolsPresent();
      final FakeFiles files = FakeFiles();

      final RunRecord record =
          await Runner(
            machine: Machine(
              shell: shell,
              files: files,
              http: FakeHttp(),
              clock: clock,
              entropy: FakeEntropy(),
            ),
            recorder: recorder,
            redactor: Redactor.none,
          ).run(
            program: deployGitops(),
            mode: Mode.run,
            header: RunRecord(
              id: const RunId('20260807T120000Z-2'),
              program: const ProgramName('deploy-gitops'),
              mode: Mode.run,
              argv: const <String>['ansiwise', 'deploy-gitops'],
              start: clock.now(),
              stage: const Stage('dev'),
              role: const Role('master'),
              fqdn: const Fqdn('m1.example.com'),
              commit: 'abc1234',
              fingerprint: 'f',
            ),
            answers: answered(),
          );

      expect(record.exitCode, 0);
      expect(
        shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason:
            'every gate of this program is off, so nothing is applied. What DOES run is the head '
            'gate looking for helm and kubectl, and looking is not doing — a gate that measures is '
            'the one thing allowed to run before the program decides it has nothing to do',
      );
      expect(files.written, isEmpty);
    });
  });

  group('--mode dry', () {
    test('changes nothing on the machine', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(
            'ENABLE_VAULT=true\nENABLE_IDP=true\nENABLE_ARGOCD=true\n'
            'BUILD_PLANE_FQDN=m1.example.com\nDOMAIN_SUFFIX=m1.example.com\n',
            mode: Mode.dry,
          );

      expect(it.files.written, isEmpty);
      expect(it.files.deleted, isEmpty);
      expect(
        it.shell.commands.where((Command c) => !c.observes),
        isEmpty,
        reason: 'a dry run may only run commands a step declared as observing',
      );
    });

    test('every phase is planned when the whole installation is switched on', () async {
      final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
          await run(
            'ENABLE_VAULT=true\nENABLE_IDP=true\nENABLE_ARGOCD=true\n'
            'BUILD_PLANE_FQDN=m1.example.com\nDOMAIN_SUFFIX=m1.example.com\n',
            mode: Mode.dry,
          );
      expect(
        it.record.steps.where((StepRecord step) => step.verdict is Skipped),
        isEmpty,
        reason: 'nothing is switched off on this machine',
      );
    });
  });
}

/// A machine carrying the two tools deploy-gitops is made of.
///
/// The head gate asks for them before anything is applied, so a fixture that did not answer would be
/// a machine with no helm and no cluster client — every run against it stopping at the first step,
/// which is what the gate is for and not what these fixtures are for.
///
/// The client is `microk8s`, which is the command the steps start. A bare `kubectl` exists on such
/// a machine too, as a shell alias the cluster program writes, but nothing here starts it.
FakeShell gitopsToolsPresent() => FakeShell()
  ..answers('command -v helm', '/usr/local/bin/helm\n')
  ..answers('command -v microk8s', '/snap/bin/microk8s\n');
