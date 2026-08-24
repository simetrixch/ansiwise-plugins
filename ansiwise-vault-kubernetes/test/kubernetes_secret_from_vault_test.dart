import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';
import 'package:test/test.dart';

/// The step that knows both tools, and the three things a move of it must not lose.
///
/// It reads an entry out of Vault and writes it onto a cluster, so it handles credentials the whole
/// way through. Two properties decide whether that is safe, and neither is visible from the outside:
/// the PLAN carries the keys and never the values, and the CAPTURE records whether the Secret stands
/// and never what it holds. Lose either and a credential is in a record an operator keeps.
///
/// The third property is the file: the values reach the cluster through one, never through a
/// command argument that every process on the host can read in a process listing, and it is removed
/// whether the apply worked or not.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentials = '$repository/secrets/vault-dev.txt';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String secretValue = 'not-a-real-password-it-is-a-test-fixture';
  const String staging = '/run/staging';
  const String manifest = '$staging/apps-app-credentials.yaml';

  // The one request this step sends, as the fake network is keyed: the entry the row names, on the
  // mount it names, with the axis slot filled from this run's answer.
  const String entryRead = 'GET $url/v1/secret/data/dev/app/database';

  // One deployment's layout, stated the way its program rows state it. The package itself carries
  // no layout, so the step is handed this one.
  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  const KubernetesSecretFromVault step = KubernetesSecretFromVault(
    repository: repository,
    mount: 'secret',
    path: '<stage>/app/database',
    name: 'app-credentials',
    namespace: 'apps',
    fields: <String>['PASSWORD=postgres-password', 'password=postgres-password'],
    staging: staging,
    layout: layout,
  );

  const StepName under = StepName('kubernetes_secret_from_vault');
  const String reading = 'kubectl get secret app-credentials --namespace apps -o name';

  // What the check reads: the whole object, because the fields are what it compares. The `-o name`
  // read above stays what the CAPTURE asks, which only has to know whether this run created it.
  const String readingFields = 'kubectl get secret app-credentials --namespace apps -o json';

  /// The Secret as the cluster answers it, holding [values] the way the cluster keeps them.
  ///
  /// The manifest is written with `stringData` and the API server stores base64 of the same bytes
  /// under `data`, which is what a comparison against this fixture has to meet.
  String clusterHolding(Map<String, String> values) => jsonEncode(<String, Object?>{
    'apiVersion': 'v1',
    'kind': 'Secret',
    'metadata': <String, Object?>{'name': 'app-credentials', 'namespace': 'apps'},
    'type': 'Opaque',
    'data': <String, String>{
      for (final MapEntry<String, String> value in values.entries)
        value.key: base64Encode(utf8.encode(value.value)),
    },
  });

  /// The machine as it stands before this step runs, with the Secret there or not.
  FakeFiles machineFiles() => FakeFiles(<String, String>{
    profilePath: 'global:\n  vaultUrl: $url\n',
    credentials: renderCredentials(url: url, unsealKeys: const <String>['k1'], rootToken: token),
  });

  /// A store that answers the entry read with [body], and nothing else at all.
  ///
  /// Keyed on the exact request, so a step reaching for any other path meets an empty answer and
  /// refuses rather than quietly being handed the entry it asked wrongly for.
  FakeHttp storeHolding(String body) => FakeHttp()..answers(entryRead, body: body);

  /// The entry as Vault's key-value store answers it.
  String entryHolding(String password) =>
      '{"data":{"data":{"postgres-password":"$password"},"metadata":{"version":1}}}';

  ({StepContext context, MemoryRecorder recorder}) contextOf({
    required FakeShell shell,
    required FakeFiles files,
    required Http http,
  }) {
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    return (
      context: StepContext(
        shell: RecordingShell(shell, recorder: recorder, redactor: Redactor.none, step: under),
        files: RecordingFiles(files, recorder: recorder, step: under),
        http: RecordingHttp(http, recorder: recorder, redactor: Redactor.none, step: under),
        clock: clock,
        entropy: FakeEntropy(),
        log: RecordingLogger(recorder: recorder, redactor: Redactor.none, step: under),
        step: under,
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'stage': 'dev'}),
        facts: Facts.none,
      ),
      recorder: recorder,
    );
  }

  group('what the record is allowed to carry', () {
    test('the plan names the file and the command, and no value of the Secret', () async {
      // A plan is written into the record an operator keeps and reads. What it may say is which
      // command would run against which file; what it may never say is what that file will hold.
      final FakeShell shell = FakeShell()..fails(reading);
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      final StepPlan plan = await step.plan(it.context);
      expect(plan.summary, contains(manifest));
      expect(
        plan.summary,
        isNot(contains(secretValue)),
        reason: 'a plan carrying the value puts the credential into the record',
      );
      expect(
        plan.summary,
        isNot(contains(token)),
        reason: 'the root token is how the value is read and belongs in no plan either',
      );
    });

    test('the capture records whether it stands, and never what it holds', () async {
      // What a capture returns is handed to the undo and is kept for as long as the run is. A
      // capture holding the values would carry every credential of this Secret through the whole
      // run, and reading them off the cluster to get them would be the leak by itself.
      final FakeShell shell = FakeShell()..answers(reading, 'secret/app-credentials\n');
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      final bool captured = await step.capture(it.context);
      expect(captured, isTrue);
      expect(shell.commands.single.argv, <String>[
        'kubectl',
        'get',
        'secret',
        'app-credentials',
        '--namespace',
        'apps',
        '-o',
        'name',
      ], reason: 'it asks whether the object is there, and reads nothing out of it');
    });

    test('a refusal names the field that is missing and never what it should have held', () async {
      final FakeShell shell = FakeShell()..fails(reading);
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding('{"data":{"data":{"other":"$secretValue"},"metadata":{"version":1}}}'),
      );

      await expectLater(
        step.apply(it.context),
        throwsA(
          isA<StateError>().having(
            (StateError failure) => failure.message,
            'message',
            allOf(contains('postgres-password'), isNot(contains(secretValue))),
          ),
        ),
      );
    });
  });

  group('how the values reach the cluster', () {
    test('through a file that is written, applied and removed', () async {
      // Never through a command argument: an argument is visible in a process listing to every
      // process on the host, and the value stands there for as long as the apply takes.
      final FakeShell shell = FakeShell()..fails(reading);
      final FakeFiles files = machineFiles();
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: files,
        http: storeHolding(entryHolding(secretValue)),
      );

      await step.apply(it.context);

      expect(files.written, <String>[manifest]);
      expect(files.deleted, <String>[manifest]);
      expect(shell.commands.single.argv, <String>[
        'kubectl',
        'apply',
        '--filename',
        manifest,
      ], reason: 'the command names the file and carries no value of its own');
      for (final Command ran in shell.commands) {
        expect(ran.argv.join(' '), isNot(contains(secretValue)));
      }
    });

    test('and the file is removed even when the apply failed', () async {
      // In a finally: a failed apply would otherwise leave every value of the Secret standing in
      // the clear on the machine, and a failed run is exactly when nobody goes back to look.
      final FakeShell shell = FakeShell()
        ..fails(reading)
        ..fails('kubectl apply --filename $manifest', stderr: 'the server rejected it');
      final FakeFiles files = machineFiles();
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: files,
        http: storeHolding(entryHolding(secretValue)),
      );

      await expectLater(step.apply(it.context), throwsA(isA<CommandFailed>()));
      expect(files.deleted, <String>[manifest]);
    });

    test('one field can reach two keys, because each side was named by whoever reads it', () {
      // The whole reason a credential is held in one place and materialized rather than minted
      // where it is needed: two components need the same value under two names.
      expect(
        step.manifestOf(const <String, String>{'PASSWORD': secretValue, 'password': secretValue}),
        contains('  PASSWORD: "$secretValue"'),
      );
      expect(
        step.manifestOf(const <String, String>{'password': secretValue}),
        contains('  password: "$secretValue"'),
      );
    });

    // A SECRET NOTHING SELECTS ON CARRIES NO LABELS, and one that is selected on carries exactly the
    // ones the row names. The pair fails in opposite directions: drop the labels from the manifest
    // and the second goes red; write a labels block for a row that named none and the first does.
    // Measured before this existed: a reader that resolves `$secret:key` against LABELLED Secrets
    // only never saw an unlabelled one, so the reference stayed unresolved — and an unresolved
    // reference travels as an EMPTY secret, which the far side reports as a credential that is
    // wrong rather than one that is missing.
    test('a row that names no label writes none', () {
      expect(step.manifestOf(const <String, String>{'k': 'v'}), isNot(contains('labels')));
    });

    test('a row that names labels writes them under metadata', () {
      const KubernetesSecretFromVault selected = KubernetesSecretFromVault(
        repository: '/srv/tree',
        layout: layout,
        mount: 'secret',
        path: 'dev/idp/bootstrap',
        name: 'reader-oidc',
        namespace: 'reader',
        labels: <String>['example.test/part-of=reader'],
        fields: <String>['clientSecret=oidc-client-secret'],
        staging: '/run/ansiwise',
      );

      final String manifest = selected.manifestOf(const <String, String>{'clientSecret': 'x'});
      expect(manifest, contains('  labels:'));
      expect(manifest, contains('    example.test/part-of: "reader"'));
    });

    test('every value is quoted, so one that is all digits is not read as a number', () {
      // The API server refuses the object for a type nobody gave it, and the message is about the
      // type rather than about the quoting.
      expect(step.manifestOf(const <String, String>{'pin': '0123'}), contains('  pin: "0123"'));
    });
  });

  group('the axis the row names', () {
    test('fills the entry path and the credential file from the same answer', () async {
      // The word is the product's and not this package's: the row names the answer under
      // `run_answer`, and every slot spelled with that name is filled from this run.
      final FakeShell shell = FakeShell()..fails(reading);
      final FakeHttp http = storeHolding(entryHolding(secretValue));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: http,
      );

      await step.apply(it.context);
      expect(http.sent.single, entryRead);
    });

    test('a slot no answer fills refuses rather than reading an entry nobody named', () async {
      // The refusal carries the slot as it stands, so the operator sees the name that was never
      // filled instead of a path with a hole in it.
      const KubernetesSecretFromVault misspelled = KubernetesSecretFromVault(
        repository: repository,
        mount: 'secret',
        path: '<stag>/app/database',
        name: 'app-credentials',
        namespace: 'apps',
        fields: <String>['PASSWORD=postgres-password'],
        staging: staging,
        layout: layout,
      );
      final FakeShell shell = FakeShell()..fails(reading);
      final FakeHttp http = storeHolding(entryHolding(secretValue));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: http,
      );

      await expectLater(
        misspelled.apply(it.context),
        throwsA(
          isA<StateError>().having(
            (StateError failure) => failure.message,
            'message',
            contains('<stag>'),
          ),
        ),
      );
      expect(http.sent, isEmpty, reason: 'a path with an unfilled slot must not reach the store');
    });
  });

  group('taking it back', () {
    test('a Secret that was already there is left standing', () async {
      // The delete removes the object whether or not this run wrote it, and every pod that mounts
      // it is then a pod that cannot start.
      final FakeShell shell = FakeShell();
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      await step.undo(it.context, true);
      expect(shell.commands, isEmpty);
    });

    test('one this run created is deleted by name', () async {
      final FakeShell shell = FakeShell();
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      await step.undo(it.context, false);
      expect(shell.commands.single.argv, <String>[
        'kubectl',
        'delete',
        'secret',
        'app-credentials',
        '--namespace',
        'apps',
        '--ignore-not-found',
      ]);
    });
  });

  /// What the check measures, which is the FIELDS and not the existence of an object.
  ///
  /// The defect this replaces: the check ran `-o name` and reported satisfied on anything that came
  /// back, saying the Secret carried what the entry held while never having looked. Measured on a
  /// live installation as an entry of six fields against a Secret of five, satisfied five runs in a
  /// row — so the innocent case below and the two red ones are the same measurement written as
  /// tests.
  group('what the check compares', () {
    test('a Secret carrying every field this row writes is satisfied', () async {
      final FakeShell shell = FakeShell()
        ..answers(
          readingFields,
          clusterHolding(<String, String>{'PASSWORD': secretValue, 'password': secretValue}),
        );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      final CheckResult answer = await step.check(it.context);
      expect(answer, isA<Satisfied>());
      expect(
        (answer as Satisfied).because,
        'app-credentials in apps carries every field this row writes',
        reason: 'the sentence says what was compared, not what the entry as a whole holds',
      );
      expect(shell.commands.single.observes, isTrue);
    });

    test('a Secret missing a field the entry gained is work to do', () async {
      // The measured case: the entry gained a field, the Secret never did, and every run reported
      // the row satisfied until somebody deleted the Secret by hand.
      final FakeShell shell = FakeShell()
        ..answers(readingFields, clusterHolding(<String, String>{'PASSWORD': secretValue}));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      expect(await step.check(it.context), isA<Ready>());
      expect(it.recorder.logLines.single, contains('password'));
      expect(
        it.recorder.logLines.single,
        isNot(contains(secretValue)),
        reason: 'the key of a field that differs is named, and never what it should have held',
      );
    });

    test('a Secret holding a value the entry has since rotated is work to do', () async {
      // Existence has not changed, so the defect this replaces could not see this one either.
      final FakeShell shell = FakeShell()
        ..answers(
          readingFields,
          clusterHolding(<String, String>{
            'PASSWORD': 'the-value-before-it-was-rotated',
            'password': secretValue,
          }),
        );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: storeHolding(entryHolding(secretValue)),
      );

      expect(await step.check(it.context), isA<Ready>());
      expect(it.recorder.logLines.single, contains('PASSWORD'));
    });

    test(
      'a Secret that is not there at all is work to do, and the store is not read for it',
      () async {
        // An absent Secret is work to do whatever the entry holds, so a dry run on a machine whose
        // entry an earlier row has not written yet never reaches the store.
        final FakeShell shell = FakeShell()..fails(readingFields);
        final FakeHttp http = storeHolding(entryHolding(secretValue));
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          shell: shell,
          files: machineFiles(),
          http: http,
        );

        expect(await step.check(it.context), isA<Ready>());
        expect(http.sent, isEmpty);
      },
    );

    test(
      'a client that exits zero without answering an object blocks rather than deciding',
      () async {
        // A wrapped client that cannot reach the cluster writes its refusal on its output and exits
        // zero. Read as "the object holds nothing", that is a Secret rewritten on every run; read as
        // "the object is fine", it is a Secret nobody ever repairs.
        final FakeShell shell = FakeShell()..answers(readingFields, 'insufficient permissions\n');
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          shell: shell,
          files: machineFiles(),
          http: storeHolding(entryHolding(secretValue)),
        );

        final CheckResult answer = await step.check(it.context);
        expect(answer, isA<Blocked>());
        expect((answer as Blocked).reason, contains('app-credentials in apps'));
      },
    );

    test('a Secret that stands while the entry cannot be read blocks', () async {
      // Nothing to compare it against. Satisfied would be a claim about the store nothing measured,
      // and ready would send an apply that is going to refuse for the same reason.
      final FakeShell shell = FakeShell()
        ..answers(
          readingFields,
          clusterHolding(<String, String>{'PASSWORD': secretValue, 'password': secretValue}),
        );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: FakeHttp()..answers(entryRead, status: 404),
      );

      final CheckResult answer = await step.check(it.context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('secret/data/dev/app/database'));
    });

    test('a second run of the whole step finds nothing to do', () async {
      // The double run this package's idempotence rests on: the apply writes the Secret, the fake
      // cluster answers with what was written, and the check that follows is the postcondition.
      final FakeShell shell = FakeShell()..fails(readingFields);
      final FakeFiles files = machineFiles();
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: files,
        http: storeHolding(entryHolding(secretValue)),
      );
      shell.changes(
        'kubectl apply --filename $manifest',
        () => shell.answers(
          readingFields,
          clusterHolding(<String, String>{'PASSWORD': secretValue, 'password': secretValue}),
        ),
      );

      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);
      expect(await step.check(it.context), isA<Satisfied>());
      expect(files.written, <String>[manifest], reason: 'the second run writes nothing again');
    });
  });

  test('a wrapped client is invoked word for word, in front of every subcommand', () async {
    final KubernetesSecretFromVault wrapped = KubernetesSecretFromVault.fromArguments(
      const Arguments(<String, Object>{
        'repository': repository,
        'mount': 'secret',
        'path': '<stage>/app/database',
        'name': 'app-credentials',
        'namespace': 'apps',
        'fields': <String>['PASSWORD=postgres-password'],
        'staging': staging,
        'kubectl': <String>['wrapper', 'kubectl'],
        'profile_path': 'cluster/profile.yaml',
        'vault_url_key': 'global.vaultUrl',
        'cluster_name_key': 'global.clusterName',
        'kubernetes_auth_path_key': 'global.vaultKubernetesAuthPath',
        'credentials_path': 'secrets/vault-<stage>.txt',
        'run_answer': 'stage',
      }),
    );
    final FakeShell shell = FakeShell()..fails('wrapper $reading');
    final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
      shell: shell,
      files: machineFiles(),
      http: storeHolding(entryHolding(secretValue)),
    );

    await wrapped.apply(it.context);
    expect(shell.commands.single.argv, <String>[
      'wrapper',
      'kubectl',
      'apply',
      '--filename',
      manifest,
    ]);
  });
}
