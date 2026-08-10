import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

import 'vault_test.dart' show ScriptedHttp, answer;

/// The one step of this package that knows a second tool, and the two things a move of it must not
/// lose.
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

  /// The machine as it stands before this step runs, with the Secret there or not.
  FakeFiles machineFiles() => FakeFiles(<String, String>{
    profilePath: 'global:\n  vaultUrl: $url\n',
    credentials: renderCredentials(url: url, unsealKeys: const <String>['k1'], rootToken: token),
  });

  /// A Vault that answers the entry read with [body].
  ScriptedHttp storeHolding(String body) =>
      ScriptedHttp((HttpRequest request, int nth) => answer(body));

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
      expect(
        shell.commands.single.argv,
        <String>[
          'kubectl',
          'get',
          'secret',
          'app-credentials',
          '--namespace',
          'apps',
          '-o',
          'name',
        ],
        reason: 'it asks whether the object is there, and reads nothing out of it',
      );
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
      expect(
        shell.commands.single.argv,
        <String>['kubectl', 'apply', '--filename', manifest],
        reason: 'the command names the file and carries no value of its own',
      );
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
      final ScriptedHttp http = storeHolding(entryHolding(secretValue));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: machineFiles(),
        http: http,
      );

      await step.apply(it.context);
      expect(http.sent.single.url, '$url/v1/secret/data/dev/app/database');
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
      final ScriptedHttp http = storeHolding(entryHolding(secretValue));
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

  test('the check asks whether it stands and never what it holds', () async {
    final FakeShell shell = FakeShell()..answers(reading, 'secret/app-credentials\n');
    final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
      shell: shell,
      files: machineFiles(),
      http: storeHolding(entryHolding(secretValue)),
    );

    expect(await step.check(it.context), isA<Satisfied>());
    expect(shell.commands.single.observes, isTrue);
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
