// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io' show Directory, File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
// The slots this program's rows write are the vault package's notation, and the handoff is a row
// against the kubernetes package. What this file measures about either is the PROGRAM's, and the
// program is this package's.
import 'package:ansiwise_vault/ansiwise_vault.dart';
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
  /// The slot this product's rows write where its stage belongs.
  ///
  /// The product's own text, and no longer any tool package's: those steps take the NAME of the
  /// answer as an argument and hold no word of their own. The program is where the two meet, and
  /// the tests below read its `run_answer` back to prove that this is the same word.
  const String stagePlaceholder = '<stage>';

  /// The step the handoff is a row against.
  ///
  /// A capability of the kubernetes package and no longer a step of this one: applying a manifest
  /// whose objects a controller then owns is the same act whatever the manifest declares, and what
  /// makes THIS one the handoff is the four values in the row.
  const StepName handoffStep = StepName('kubernetes_object_irreversible');

  // The six plugins the shipped configuration turns on, composed the way the binary composes
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
      expect(everywhere, containsAll(<String>['admin', 'controller', 'manager-host']));
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
          // The manager's two identities, and they are two on purpose: `manager` is the workload
          // itself, `manager-host` is the read side of its own tier, which exists so that nothing
          // else in that namespace reaches it.
          'manager',
          'manager-host',
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
      reason:
          'the system tier holds the read half of the repository credential, and the tier exists '
          'so that no workload namespace reaches it',
    );
  });

  // WHAT THIS GROUP MEASURES, AND WHAT IT DOES NOT. It holds one link of the chain: every entry a
  // program writes is granted by a policy that some auth role of this program hands out. That is not
  // the whole of "a reader can reach it". A login also has to be admitted, and this looks at nothing
  // about that: an auth role binds a service account IN NAMED NAMESPACES, and a reader installed into
  // a namespace the role does not bind is refused before any policy is consulted.
  //
  // The unmeasured half is not hypothetical — it is where two live defects were found. Measuring it
  // means reading which namespace each application is installed into, and that stands in the chart
  // tree rather than in the programs this suite already resolves.
  //
  // The name says the link, not the chain, because a group titled for the chain reports a green over
  // a read that fails at login.
  group('every credential the seed writes is granted by a policy some role hands out', () {
    /// The entries the programs of this installation write, as the path each one is read back at.
    ///
    /// EVERY program and not this one alone. The policies and the roles exist only here, so an entry
    /// written by another program is an entry no policy of this installation grants — which is the
    /// very thing this group is asked to report, and a scan limited to this file would answer that
    /// there was nothing to look at.
    List<String> writtenEntries() => <String>[
      for (final File file in Directory(
        installationProgramsRoot,
      ).listSync().whereType<File>().where((File each) => each.path.endsWith('.yaml')))
        for (final ProgramStep entry in loadProgram(
          file.readAsStringSync(),
          where: file.uri.pathSegments.last,
        ).steps)
          if (entry.step == const StepName('vault_kv_entry'))
            '${entry.arguments.text('mount')}/data/${entry.arguments.text('path')}',
    ];

    /// The paths each policy of this program grants READ on, by the name it is written under.
    ///
    /// A grant that interpolates the caller's own identity is left out: it never names a literal
    /// path, so it can cover no entry written from a program file, and reading one as coverage would
    /// report every entry as reachable by everything.
    Map<String, List<String>> readGrants() {
      final Map<String, List<String>> granted = <String, List<String>>{};
      for (final ProgramStep entry in program().steps) {
        if (entry.step != const StepName('vault_policy')) {
          continue;
        }
        for (final String line in grantsOf(entry).split('\n')) {
          if (line.contains('{{') || !line.contains('"read"')) {
            continue;
          }
          final RegExpMatch? path = RegExp(r'path\s+"([^"]+)"').firstMatch(line);
          if (path?.group(1) case final String on) {
            granted.putIfAbsent(entry.arguments.text('name'), () => <String>[]).add(on);
          }
        }
      }
      return granted;
    }

    /// The policies some auth role of this program hands out.
    ///
    /// Read out of the role body's own list and not out of the whole body, so a policy is not
    /// counted as carried because a role happens to bind an ACCOUNT of the same name.
    Set<String> carriedPolicies() => <String>{
      for (final ProgramStep entry in program().steps)
        if (entry.step == const StepName('vault_auth_role'))
          for (final RegExpMatch each in RegExp(
            r'"token_policies"\s*:\s*\[([^\]]*)\]',
          ).allMatches(entry.arguments.text('body')))
            ...RegExp(
              r'"([^"]+)"',
            ).allMatches(each.group(1) ?? '').map((RegExpMatch policy) => policy.group(1) ?? ''),
    };

    /// Whether [grant] covers [entry], by the two wildcards a grant may carry.
    ///
    /// `*` stands for the rest of the path and `+` for one segment of it. Nothing else: a grant is
    /// matched the way the store matches it, and a looser reading here would call an entry covered
    /// that the store refuses at run time.
    bool covers(String grant, String entry) {
      if (!grant.contains('*') && !grant.contains('+')) {
        return grant == entry;
      }
      final String pattern = grant
          .split('/')
          .map((String part) => part == '+' ? '[^/]+' : RegExp.escape(part).replaceAll(r'\*', '.*'))
          .join('/');
      return RegExp('^$pattern\$').hasMatch(entry);
    }

    /// The entries no policy of this program grants, and why each of them is right.
    ///
    /// Named one by one rather than counted, and each one is a claim about a reader: an entry here
    /// is read by something other than a workload logging in through this cluster's auth mount. An
    /// entry that lands here by accident is a credential written where nothing can read it, which is
    /// what the rest of this group exists to refuse.
    const Map<String, String> readByNoPolicy = <String, String>{
      'secret/data/$stagePlaceholder/idp/database':
          'this program materializes it onto the cluster itself, with the root token, in the row '
          'that puts the identity provider\'s credentials in front of its release',
      'secret/data/$stagePlaceholder/system/argocd/repo-read-pat':
          'the system tier, which no policy here grants a workload on purpose — what syncs on a '
          'cluster of this installation reads a copy of its own under the slaves tier',
    };

    test('there are entries and policies to measure', () {
      // Without this the check below is satisfied by a program that seeds nothing, and empty
      // against empty is not agreement.
      expect(writtenEntries(), isNotEmpty);
      expect(readGrants(), isNotEmpty);
      expect(carriedPolicies(), isNotEmpty);
    });

    test('each one is granted by a policy some role hands out, or is named as read otherwise', () {
      final Map<String, List<String>> granted = readGrants();
      final Set<String> carried = carriedPolicies();
      for (final String entry in writtenEntries()) {
        if (readByNoPolicy.containsKey(entry)) {
          continue;
        }
        final List<String> readers = <String>[
          for (final MapEntry<String, List<String>> policy in granted.entries)
            if (policy.value.any((String grant) => covers(grant, entry)))
              if (carried.contains(policy.key)) policy.key,
        ];
        expect(
          readers,
          isNotEmpty,
          reason:
              'nothing can read $entry: no policy of this program grants read on it under a name '
              'some auth role hands out. The seed writes the credential, the run comes back green, '
              'and whatever needs it is refused at its first read — days later, with a message '
              'about what it could not do rather than about the credential nobody could reach. If '
              'its reader is not a workload of this cluster, name it in readByNoPolicy with the '
              'reader',
        );
      }
    });

    test('the entry the program says has no writer still has none', () {
      // The program states, beside the row that writes the other entry of that tier, that nothing
      // here writes the manager's key to this host and what the installation cannot do without it.
      // That sentence is the only place an operator is told, so it may not quietly stop being true:
      // the day a row writes this entry, the paragraph saying there is none goes with it.
      expect(
        writtenEntries(),
        isNot(contains('secret/data/$stagePlaceholder/manager-host/ssh')),
        reason:
            'a row writes this entry now, so the paragraph above the manager-host seed row in '
            'deploy-gitops.yaml claims a gap that is closed — delete it, and with it the sentence '
            'saying the manager cannot add a cluster to this installation',
      );
    });

    test('nothing is excused that no row writes', () {
      // The probe on the exception list. A path that stops being written leaves its excuse behind,
      // and from then on the check above passes over a name that means nothing.
      expect(
        readByNoPolicy.keys.toSet().difference(writtenEntries().toSet()),
        isEmpty,
        reason: 'this entry is excused from needing a policy and no row of any program writes it',
      );
    });
  });

  test('the handoff is the last step and it carries a verdict of its own', () async {
    final List<StepName> order = <StepName>[
      for (final ResolvedStep step in deployGitops().steps) step.entry.step,
    ];
    expect(order.last, handoffStep);

    final ({RunRecord record, FakeShell shell, FakeFiles files, MemoryRecorder recorder}) it =
        await run('ENABLE_ARGOCD=true\n');
    final StepRecord handoff = it.record.steps.firstWhere(
      (StepRecord step) => step.step == handoffStep,
    );
    expect(
      handoff.verdict,
      isNot(isA<Skipped>()),
      reason: 'the handoff is a recorded step and not the absence of an error',
    );
  });

  group('what the handoff row says', () {
    /// The handoff as the resolver hands it to the engine, defaults folded in.
    ///
    /// Read RESOLVED rather than off the file, because two of the four values it turns on are
    /// written once for the whole program: which answer fills the manifest's slot, and how the
    /// cluster client is invoked. Asked of the file alone, a correct program would read as a row
    /// missing them.
    ResolvedStep handoff() =>
        deployGitops().steps.firstWhere((ResolvedStep step) => step.entry.step == handoffStep);

    test('it is the kind that cannot be taken back, and not the ordinary apply', () {
      // The difference is not a nicety. The ordinary row's undo deletes what its manifest names,
      // and deleting this object takes every application the reconciler made from it — none of
      // which this run applied. The row that ends this program has to be the other kind.
      expect(program().steps.where((ProgramStep entry) => entry.step == handoffStep), hasLength(1));
      expect(handoff().registered.create(handoff().entry.arguments), isA<IrreversibleStep>());
    });

    test('the manifest is the row\'s, with the stage in a marked slot', () {
      // The path is the row's to say; what the row cannot say is which stage this installation
      // runs, so that one value stands as a slot and the run fills it. The name of the answer that
      // fills it is stated once for the whole program, in its defaults block, which is what stops
      // the slot and the answer coming apart.
      expect(handoff().entry.arguments.text('manifest'), 'argocd/$stagePlaceholder/root-app.yaml');
      expect(
        handoff().entry.arguments.text('run_answer'),
        'stage',
        reason: 'the slot and the answer that fills it have to be the same word',
      );
    });

    test('the repair is the command that puts the manifest back', () {
      // The tool package knows how a manifest is applied and nothing about the branch it stands in,
      // so a refusal composed there could only name the missing path. The operator needs the act.
      expect(
        handoff().entry.arguments.text('repair'),
        contains('git -C /srv/hostyour-cloud merge master'),
      );
    });

    test('the reason says what is lost, not that no undo was written', () {
      final String why = handoff().entry.arguments.text('irreversible_reason');
      expect(why, contains('reconciler'));
      expect(
        why.toLowerCase(),
        isNot(anyOf(equals('irreversible'), contains('not implemented'))),
        reason: 'this is what a dry run shows the operator at the point of no return',
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
  ..answers(onThePathKey('helm'), '/usr/local/bin/helm\n')
  ..answers(onThePathKey('microk8s'), '/snap/bin/microk8s\n');
