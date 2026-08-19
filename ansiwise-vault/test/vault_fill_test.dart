import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

// The scripted network port is defined once, beside the steps it was written for, and shown here
// rather than written a second time — a fake that exists twice is a fake that drifts.
import 'vault_test.dart' show ScriptedHttp, answer;

/// Filling the store: the shape callers authenticate against, and the values behind it.
///
/// The properties here are the ones that make a re-run safe. A seed has no transaction, so
/// everything it refuses it refuses before the first write; and a second run of it has to write
/// nothing at all, or every re-run of the installer rotates values that running callers read
/// once.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentials = '$repository/secrets/vault-dev.txt';
  const String secrets = '$repository/secrets/secrets.dev';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String clusterName = 'm1';
  const String authMount = 'kubernetes-m1';

  // One deployment's layout, stated the way its program rows state it. The package itself carries
  // no layout, so every step in this file is handed these.
  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  /// The slot this deployment's rows write. It is the deployment's own text and not the package's:
  /// nothing in the vault package knows the word, and the test below is what holds the two together.
  const String stagePlaceholder = '<stage>';
  const String secretsPath = 'secrets/secrets.<stage>';

  /// The profile as the deployment writes it, which is where every step reads these three.
  const String profile =
      'global:\n'
      '  vaultUrl: $url\n'
      '  clusterName: $clusterName\n'
      '  vaultKubernetesAuthPath: $authMount\n';

  final String credentialFile = renderCredentials(
    url: url,
    unsealKeys: const <String>['k1', 'k2', 'k3'],
    rootToken: token,
  );

  ({StepContext context, MemoryRecorder recorder}) contextOf({
    required FakeFiles files,
    required Http http,
    String step = 'vault_kv_entry',
    Arguments answers = const Arguments(<String, Object>{'stage': 'dev'}),
  }) {
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final StepName name = StepName(step);
    return (
      context: StepContext(
        shell: RecordingShell(FakeShell(), recorder: recorder, redactor: Redactor.none, step: name),
        files: RecordingFiles(files, recorder: recorder, step: name),
        http: RecordingHttp(http, recorder: recorder, redactor: Redactor.none, step: name),
        clock: clock,
        entropy: FakeEntropy(),
        log: RecordingLogger(recorder: recorder, redactor: Redactor.none, step: name),
        step: name,
        arguments: Arguments.none,
        answers: answers,
        facts: Facts.none,
      ),
      recorder: recorder,
    );
  }

  FakeFiles machineWith(String secretsFile) => FakeFiles(<String, String>{
    profilePath: profile,
    credentials: credentialFile,
    secrets: secretsFile,
  });

  group('a generated field', () {
    const VaultKvEntry minting = VaultKvEntry(
      repository: repository,
      mount: 'secret',
      path: 'build/catalog/repo-pat',
      fields: <String>['pat=CATALOG_REPO_PAT'],
      mint: <String>['pat'],
      fieldsOwnedElsewhere: <String>[],
      optionalFields: <String>[],
      copyFrom: <String>[],
      layout: layout,
      secrets: secretsPath,
    );

    test('an empty variable is no longer a refusal, it is something to make', () async {
      // Without this the run stops and tells an operator to invent an OIDC client secret by hand,
      // which is how a weak one gets into the one component everything authenticates against.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      expect(await minting.check(it.context), isA<Ready>());
    });

    test('a read that FAILED is not an entry that holds nothing', () async {
      // THE PLANTED DEFECT, and it is the one that destroys something. A 403 while a policy is being
      // written is not 404, so it used to fall to the same side as "there is nothing there" — and
      // what followed was a fresh secret over a live one, with the run reporting success because
      // from the step's own view it wrote what was missing.
      for (final int status in <int>[403, 500]) {
        final ScriptedHttp http = ScriptedHttp(
          (HttpRequest request, int nth) => request.method == 'GET'
              ? answer('{"errors":["permission denied"]}', status: status)
              : answer(''),
        );
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          files: machineWith('CATALOG_REPO_PAT=\n'),
          http: http,
        );

        expect(
          await minting.check(it.context),
          isA<Blocked>(),
          reason: '$status says neither what the entry holds nor that it holds nothing',
        );
        await expectLater(
          minting.apply(it.context),
          throwsA(isA<StateError>()),
          reason: 'and apply must not mint over what it could not read',
        );
      }
    });

    test('an answer whose body will not decode is refused too', () async {
      // The other half of unreadable: the status says yes and the body is a gateway's error page.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('<html>502 Bad Gateway</html>') : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      expect(await minting.check(it.context), isA<Blocked>());
    });

    test('THE INNOCENT NEIGHBOUR: a genuine 404 still mints', () async {
      // Without this the refusal above would mean nothing: a step that refused every read would pass
      // it and never create an entry at all.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      expect(await minting.check(it.context), isA<Ready>());
      await minting.apply(it.context);
    });

    test('an entry that already carries it is finished, and nothing is generated', () async {
      // The whole of create-only. Generating again writes a value into the store that whatever is
      // already using the old one cannot know, and there is no way back to it.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'data': <String, Object?>{'pat': 'aaaabbbbccccdddd'},
            },
          }),
        ),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      expect(await minting.check(it.context), isA<Satisfied>());
    });

    test('an entry carrying it EMPTY is not carrying it', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'data': <String, Object?>{'pat': ''},
            },
          }),
        ),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      expect(await minting.check(it.context), isA<Ready>());
    });

    test('what is written is generated, and it is not the empty string', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      await minting.apply(it.context);

      final HttpRequest written = http.sent.lastWhere((HttpRequest one) => one.method != 'GET');
      final Map<String, Object?> body = jsonDecode(written.body ?? '{}') as Map<String, Object?>;
      final Map<String, Object?> data = body['data']! as Map<String, Object?>;
      // The fake source's first draw, at the length the step asks for. Asserted against the
      // constant rather than against a literal of sixty-four characters, because that is a literal
      // somebody miscounts — and a value four characters short would still look right.
      expect(data['pat'], startsWith('fa4e0001'));
      expect(data['pat'], hasLength(VaultKvEntry.mintedBytes * 2));
      expect(data['pat'], matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('a value the entry already holds is written back unchanged', () async {
      // A write to this store replaces the whole entry, so a generated field that is not carried
      // forward is a generated field silently rotated by the next run.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => request.method == 'GET'
            ? answer(
                jsonEncode(<String, Object?>{
                  'data': <String, Object?>{
                    'data': <String, Object?>{'pat': 'aaaabbbbccccdddd'},
                  },
                }),
              )
            : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=\n'),
        http: http,
      );

      await minting.apply(it.context);

      final HttpRequest written = http.sent.lastWhere((HttpRequest one) => one.method != 'GET');
      final Map<String, Object?> body = jsonDecode(written.body ?? '{}') as Map<String, Object?>;
      expect((body['data']! as Map<String, Object?>)['pat'], 'aaaabbbbccccdddd');
    });
  });

  group('the values', () {
    test('a second run writes nothing again', () async {
      // A put on this mount makes a new version every time it is called, so "already right" has to
      // be measured rather than assumed — otherwise every re-run of the installer rewrites every
      // value the store is holding.
      final Map<String, Object?> stored = <String, Object?>{
        'data': <String, Object?>{
          'data': <String, Object?>{'pat': 'ghp_notarealcredential'},
        },
      };
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer(jsonEncode(stored)),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=ghp_notarealcredential\n'),
        http: http,
      );

      const VaultKvEntry step = VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: 'build/catalog/repo-pat',
        fields: <String>['pat=CATALOG_REPO_PAT'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>[],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      );

      expect(await step.check(it.context), isA<Satisfied>());
      expect(
        http.sent.where((HttpRequest request) => request.method != 'GET'),
        isEmpty,
        reason: 'nothing was sent that changes anything',
      );
    });

    test('a value that differs is written, and the record never says what it is', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=ghp_notarealcredential\n'),
        http: http,
      );

      const VaultKvEntry step = VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: 'build/catalog/repo-pat',
        fields: <String>['pat=CATALOG_REPO_PAT'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>[],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      );
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      final HttpRequest written = http.sent.lastWhere(
        (HttpRequest request) => request.method == 'POST',
      );
      expect(written.body, contains('ghp_notarealcredential'));

      final String record = it.recorder.events
          .map((RunEvent event) => jsonEncode(const RecordCodec().event(event)))
          .join('\n');
      expect(
        record,
        isNot(contains('ghp_notarealcredential')),
        reason: 'what a request carries is not what the record carries',
      );
    });

    test('an entry left with no fields is skipped and never written as nothing', () async {
      // A put of an empty object replaces the entry with nothing. The signing key of this entry
      // belongs to another writer, so a run that finds it unfilled must leave the entry alone.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('', status: 404),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith("POSTFIX_DKIM_PRIVATE_KEY='<paste PEM here>'\n"),
        http: http,
      );

      const VaultKvEntry step = VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: 'dev/app/postfix',
        fields: <String>['dkim-private-key=POSTFIX_DKIM_PRIVATE_KEY'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>['dkim-private-key'],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      );

      final CheckResult result = await step.check(it.context);
      expect(result, isA<Satisfied>());
      await step.apply(it.context);
      expect(http.sent.where((HttpRequest request) => request.method != 'GET'), isEmpty);
    });

    test('an unfilled value nobody else owns is refused by the name of its variable', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=<fill this in>\nGITOPS_REPO_PAT=\n'),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('', status: 404)),
      );

      final CheckResult result = await const VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: 'build/catalog/repo-pat',
        fields: <String>['pat=CATALOG_REPO_PAT', 'other=GITOPS_REPO_PAT'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>[],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      ).check(it.context);

      expect(result, isA<Blocked>());
      // Everything wrong at once. One variable per run is five runs to learn five things, and every
      // one of those runs writes.
      expect((result as Blocked).reason, contains('CATALOG_REPO_PAT'));
      expect(result.reason, contains('GITOPS_REPO_PAT'));
    });

    test('a hand-filled input with carriage returns is refused before any write', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('', status: 404),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith('CATALOG_REPO_PAT=ghp_notarealcredential\r\n'),
        http: http,
      );

      final CheckResult result = await const VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: 'build/catalog/repo-pat',
        fields: <String>['pat=CATALOG_REPO_PAT'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>[],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('carriage return'));
      expect(http.sent.where((HttpRequest request) => request.method != 'GET'), isEmpty);
    });
  });

  group('the stage in a policy path', () {
    // A policy that grants on the wrong stage's tree is accepted by Vault and reported as written.
    // Nothing about it looks wrong until a caller is refused, so the stage is a marked slot the run
    // fills, and a stage written out in full is refused instead.

    const VaultPolicy scoped = VaultPolicy(
      repository: repository,
      name: '$clusterPlaceholder-eso',
      rules:
          'path "secret/data/$stagePlaceholder/app/*" { capabilities = ["read"] }\n'
          'path "secret/metadata/$stagePlaceholder/app/*" { capabilities = ["read", "list"] }\n',
      layout: layout,
    );

    /// The policy text [scoped] would send on an installation whose stage is [stage].
    Future<String> writtenUnder(String stage) async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{
          profilePath: profile,
          '$repository/secrets/vault-$stage.txt': credentialFile,
        }),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('', status: 404)),
        step: 'vault_policy',
        answers: Arguments(<String, Object>{'stage': stage}),
      );
      final StepPlan plan = await scoped.plan(it.context);
      return (plan as RequestPlan).body ?? '';
    }

    test('is filled in by the step, on the data path and the metadata path alike', () async {
      expect(
        await writtenUnder('dev'),
        'path "secret/data/dev/app/*" { capabilities = ["read"] }\n'
        'path "secret/metadata/dev/app/*" { capabilities = ["read", "list"] }\n',
      );
    });

    test("is THIS run's stage and not a remembered one", () async {
      // The same step under prod. A step that read the stage from anywhere but the run would pass
      // the test above and still grant a prod installation on the dev tree.
      final String dev = await writtenUnder('dev');
      final String prod = await writtenUnder('prod');

      expect(prod, contains('secret/data/prod/app/*'));
      expect(prod, isNot(contains('dev')));
      expect(
        dev,
        isNot(prod),
        reason: 'one text under two stages is one of the two granting on the other\'s tree',
      );
    });

    test('written out in full is REFUSED, naming what it should have been', () async {
      // Without this a rule copied from a working installation carries that installation's stage,
      // and nothing reports it: Vault writes the policy and the first sign is a caller refused.
      const VaultPolicy wrong = VaultPolicy(
        repository: repository,
        name: '$clusterPlaceholder-eso',
        rules: 'path "secret/data/dev/app/*" { capabilities = ["read"] }\n',
        layout: layout,
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{}')),
        step: 'vault_policy',
      );

      final CheckResult result = await wrong.check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('names the stage "dev"'));
      expect(
        result.reason,
        contains('"secret/data/$stagePlaceholder/app/*"'),
        reason: 'a refusal that does not say what to write instead costs a second run to learn it',
      );
    });

    test('a policy with no grants at all is refused rather than written', () async {
      // Vault accepts it. Every caller bound to it is then refused with a message about their own
      // token, and nothing in that message points at the policy.
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answer('{}'));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_policy',
      );

      final CheckResult result = await const VaultPolicy(
        repository: repository,
        name: '$clusterPlaceholder-eso',
        rules: '',
        layout: layout,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('no grants at all'));
      expect(http.sent, isEmpty);
    });
  });

  group("the names a program file cannot write down", () {
    // A program file ships inside the binary to every installation and nothing rewrites it, so this
    // cluster's own short name, its auth mount, the stage and the address of its Vault are marked
    // slots that the step fills from the run. Vault accepts whatever it is given: a policy written
    // under another cluster's name is created and reported as written, and the callers bound to the
    // name that was meant are refused with a message about their own tokens.

    /// The profile as the deployment writes it, naming [name] and [mount].
    String profileNaming(String name, String mount) =>
        'global:\n  vaultUrl: $url\n  clusterName: $name\n  vaultKubernetesAuthPath: $mount\n';

    /// A machine carrying that profile and the credential file, and nothing else.
    FakeFiles machineNaming(String name, String mount) => FakeFiles(<String, String>{
      profilePath: profileNaming(name, mount),
      credentials: credentialFile,
    });

    test('a policy name follows the short name and never the mount path', () async {
      // The two can agree on every installation there is — a deployment can write the mount as
      // `kubernetes-<name>` — so a rule that read whichever was at hand would pass everywhere. Here
      // they disagree, and the policy has to come out of the short name.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('', status: 404),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineNaming(clusterName, 'kubernetes-from-somewhere-else'),
        http: http,
        step: 'vault_policy',
      );

      expect(
        await const VaultPolicy(
          repository: repository,
          name: '$clusterPlaceholder-eso',
          rules: 'path "secret/data/$stagePlaceholder/app/*" { capabilities = ["read"] }\n',
          layout: layout,
        ).check(it.context),
        isA<Ready>(),
      );
      expect(http.sent.single.url, endsWith('/v1/sys/policies/acl/m1-eso'));
    });

    test('an auth mount follows its own key and is never composed from the short name', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineNaming(clusterName, 'kubernetes-from-somewhere-else'),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"data": {}}')),
        step: 'vault_auth_method',
      );

      final StepPlan plan = await const VaultAuthMethod(
        repository: repository,
        type: 'kubernetes',
        path: kubernetesMountPlaceholder,
        layout: layout,
      ).plan(it.context);

      expect(
        plan.summary,
        endsWith('/v1/sys/auth/kubernetes-from-somewhere-else'),
        reason:
            'whatever logs in through this mount reads this same key to decide where, so a mount '
            'created anywhere else is a mount nothing on the cluster reaches',
      );
    });

    test('a profile that carries no short name blocks, by file and by key', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('', status: 404),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{
          profilePath: 'global:\n  vaultUrl: $url\n',
          credentials: credentialFile,
        }),
        http: http,
        step: 'vault_policy',
      );

      final CheckResult result = await const VaultPolicy(
        repository: repository,
        name: '$clusterPlaceholder-eso',
        rules: 'path "secret/data/$stagePlaceholder/app/*" { capabilities = ["read"] }\n',
        layout: layout,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(profilePath));
      expect(result.reason, contains(layout.nameKey));
      expect(
        http.sent,
        isEmpty,
        reason: 'a policy written under a name nobody meant is created and reported as written',
      );
    });

    test('a name nothing here knows is refused rather than sent', () async {
      // A misspelled slot would otherwise reach Vault inside a policy name, be accepted there, and
      // leave every caller bound to the name that was meant refused about its own token.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('', status: 404),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineNaming(clusterName, authMount),
        http: http,
        step: 'vault_policy',
      );

      final CheckResult result = await const VaultPolicy(
        repository: repository,
        name: '<clstr>-eso',
        rules: 'path "secret/data/$stagePlaceholder/app/*" { capabilities = ["read"] }\n',
        layout: layout,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('<clstr>'));
      expect(result.reason, contains(clusterPlaceholder));
      expect(http.sent, isEmpty);
    });

    test("a role name and an entry path take THIS run's stage", () async {
      // Under prod. A stage read from anywhere but the run would bind a prod installation's
      // callers to the role a dev installation's readers log in under, and seed the dev tree.
      final ({StepContext context, MemoryRecorder recorder}) prod = contextOf(
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(clusterName, authMount),
          '$repository/secrets/vault-prod.txt': credentialFile,
          '$repository/secrets/secrets.prod': 'POSTFIX_DKIM_PRIVATE_KEY=notarealkey\n',
        }),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('', status: 404)),
        step: 'vault_auth_role',
        answers: const Arguments(<String, Object>{'stage': 'prod'}),
      );

      final StepPlan role = await const VaultAuthRole(
        repository: repository,
        mount: kubernetesMountPlaceholder,
        role: 'workload-eso-$stagePlaceholder',
        body: '{"token_policies":["$clusterPlaceholder-workload-read"]}',
        layout: layout,
      ).plan(prod.context);
      expect(role.summary, endsWith('/v1/auth/$authMount/role/workload-eso-prod'));
      expect((role as RequestPlan).body, contains('"m1-workload-read"'));

      final StepPlan entry = await const VaultKvEntry(
        repository: repository,
        mount: 'secret',
        path: '$stagePlaceholder/app/postfix',
        fields: <String>['dkim-private-key=POSTFIX_DKIM_PRIVATE_KEY'],
        mint: <String>[],
        fieldsOwnedElsewhere: <String>[],
        optionalFields: <String>[],
        copyFrom: <String>[],
        layout: layout,
        secrets: secretsPath,
      ).plan(prod.context);
      expect(entry.summary, endsWith('/v1/secret/data/prod/app/postfix'));
    });

    test('the browser role is sent back to the Vault the profile names', () async {
      // The address a browser is redirected to after logging in is the address of THIS
      // installation's Vault, and a cluster pointed at another's Vault has that one's address —
      // which only the profile records.
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineNaming(clusterName, authMount),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('', status: 404)),
        step: 'vault_auth_role',
      );

      final StepPlan plan = await const VaultAuthRole(
        repository: repository,
        mount: 'oidc',
        role: 'default',
        body:
            '{"allowed_redirect_uris":["$vaultUrlPlaceholder/ui/vault/auth/oidc/oidc/callback"],'
            '"token_policies":["admin"]}',
        layout: layout,
      ).plan(it.context);

      expect((plan as RequestPlan).body, contains('"$url/ui/vault/auth/oidc/oidc/callback"'));
    });
  });

  group('the policies', () {
    test('a templated policy is written with the accessor the store minted', () async {
      // Written the way a program file writes it: the whole path, with the stage and the accessor
      // as the two slots this run fills.
      const String rules =
          'path "secret/data/$stagePlaceholder/workload/'
          '{{identity.entity.aliases.$accessorPlaceholder.metadata.service_account_namespace}}/*" '
          '{ capabilities = ["read"] }';

      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) {
        if (request.url.endsWith('/v1/sys/auth')) {
          return answer(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'kubernetes-m1/': <String, Object?>{
                  'type': 'kubernetes',
                  'accessor': 'auth_kubernetes_1a2b3c',
                },
              },
            }),
          );
        }
        return request.method == 'GET' ? answer('', status: 404) : answer('');
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_policy',
      );

      const VaultPolicy step = VaultPolicy(
        repository: repository,
        name: '$clusterPlaceholder-workload-read',
        rules: rules,
        authMount: kubernetesMountPlaceholder,
        layout: layout,
      );
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      final HttpRequest written = http.sent.lastWhere(
        (HttpRequest request) => request.method == 'PUT',
      );
      expect(written.body, contains('auth_kubernetes_1a2b3c'));
      expect(
        written.body,
        isNot(contains('<accessor>')),
        reason:
            'a policy written with the placeholder still in it resolves every templated path to '
            'nothing, and the caller is refused with a message about its own token',
      );
    });

    test('a templated policy with no mount to template on is refused', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            answer(jsonEncode(<String, Object?>{'data': <String, Object?>{}})),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_policy',
      );

      final CheckResult result = await const VaultPolicy(
        repository: repository,
        name: '$clusterPlaceholder-workload-read',
        rules:
            'path "secret/data/$stagePlaceholder/workloads/'
            '{{identity.entity.aliases.$accessorPlaceholder.metadata.workload}}" '
            '{ capabilities = ["read"] }',
        authMount: kubernetesMountPlaceholder,
        layout: layout,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('kubernetes-m1'));
      expect(http.sent.where((HttpRequest request) => request.method != 'GET'), isEmpty);
    });

    test('a policy that already says the same thing is nothing to do', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{'policy': '\n  path "*" { capabilities = ["sudo"] }\n\n'},
          }),
        ),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_policy',
      );

      expect(
        await const VaultPolicy(
          repository: repository,
          name: 'admin',
          rules: 'path "*" { capabilities = ["sudo"] }\n',
          layout: layout,
        ).check(it.context),
        isA<Satisfied>(),
      );
    });
  });

  group('the roles', () {
    const String defaultRole =
        '{"role_type":"oidc","user_claim":"preferred_username","groups_claim":"groups",'
        '"bound_claims":{"groups":["admins"]},"token_policies":["admin"]}';

    test('a role travels as one object, so a map field arrives as a map', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_auth_role',
      );

      const VaultAuthRole step = VaultAuthRole(
        repository: repository,
        mount: 'oidc',
        role: 'default',
        body: defaultRole,
        layout: layout,
      );
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      final HttpRequest written = http.sent.lastWhere(
        (HttpRequest request) => request.method == 'POST',
      );
      final Object? sent = jsonDecode(written.body ?? '');
      expect(sent, isA<Map<String, Object?>>());
      if (sent case final Map<String, Object?> object) {
        // The expensive incident this shape exists for: sent as separate parameters through a
        // shell, this field arrived as text and the store answered that it expected a map and got
        // a string.
        expect(object['bound_claims'], isA<Map<String, Object?>>());
        expect(object['user_claim'], 'preferred_username');
      }
    });

    test('a role write keeps the namespaces something else added to it', () async {
      // A role write replaces the role whole. A list recomputed from the program file alone drops
      // every member something else added after that file was written, and the readers those
      // members admitted are then refused with "not authorized" and nothing naming why.
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) {
        if (request.method == 'GET') {
          return answer(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'bound_service_account_namespaces': <String>['controller', 's1-slave'],
              },
            }),
          );
        }
        return answer('');
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_auth_role',
      );

      const VaultAuthRole step = VaultAuthRole(
        repository: repository,
        mount: kubernetesMountPlaceholder,
        role: 'secret-reader',
        body: '{"bound_service_account_namespaces":["controller","dbgate"],"ttl":"24h"}',
        preserveList: 'bound_service_account_namespaces',
        layout: layout,
      );
      await step.apply(it.context);

      final HttpRequest written = http.sent.lastWhere(
        (HttpRequest request) => request.method == 'POST',
      );
      final Object? sent = jsonDecode(written.body ?? '');
      expect(sent, isA<Map<String, Object?>>());
      if (sent case final Map<String, Object?> object) {
        expect(
          object['bound_service_account_namespaces'],
          containsAll(<String>['controller', 'dbgate', 's1-slave']),
        );
      }
    });

    test('a read that FAILED does not drop what the role preserves', () async {
      // THE PLANTED DEFECT, and here it takes away an authorisation rather than a credential. A 403
      // or a 500 is not 404, so it used to fall to the same side as "this role does not exist yet" —
      // and the write that followed carried only what THIS run knew about, silently narrowing a role
      // that other runs and other programs had widened. preserve_list exists exactly to stop that.
      for (final int status in <int>[403, 500]) {
        final ScriptedHttp http = ScriptedHttp(
          (HttpRequest request, int nth) => request.method == 'GET'
              ? answer('{"errors":["permission denied"]}', status: status)
              : answer(''),
        );
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
          http: http,
          step: 'vault_auth_role',
        );

        const VaultAuthRole step = VaultAuthRole(
          repository: repository,
          mount: kubernetesMountPlaceholder,
          role: 'secret-reader',
          body: '{"bound_service_account_namespaces":["controller"],"ttl":"24h"}',
          preserveList: 'bound_service_account_namespaces',
          layout: layout,
        );

        expect(await step.check(it.context), isA<Blocked>());
        await expectLater(step.apply(it.context), throwsA(isA<StateError>()));
        expect(
          http.sent.where((HttpRequest request) => request.method == 'POST'),
          isEmpty,
          reason: 'nothing was written, so nothing the role carried was taken away',
        );
      }
    });

    test('THE INNOCENT NEIGHBOUR: a genuine 404 still creates the role from nothing', () async {
      // Without this the refusal above would mean nothing: a step that refused every read could
      // never create a role at all, and every installation would stop at its first one.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            request.method == 'GET' ? answer('', status: 404) : answer(''),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_auth_role',
      );

      const VaultAuthRole step = VaultAuthRole(
        repository: repository,
        mount: kubernetesMountPlaceholder,
        role: 'secret-reader',
        body: '{"bound_service_account_namespaces":["controller"],"ttl":"24h"}',
        preserveList: 'bound_service_account_namespaces',
        layout: layout,
      );

      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);
      expect(
        http.sent.where((HttpRequest request) => request.method == 'POST'),
        isNotEmpty,
        reason: 'a role that is genuinely absent is still written',
      );
    });

    test('a role that already says the same thing is nothing to do', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer(
          jsonEncode(<String, Object?>{
            'data': <String, Object?>{
              'role_type': 'oidc',
              'user_claim': 'preferred_username',
              'groups_claim': 'groups',
              'bound_claims': <String, Object?>{
                'groups': <String>['admins'],
              },
              'token_policies': <String>['admin'],
            },
          }),
        ),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_auth_role',
      );

      expect(
        await const VaultAuthRole(
          repository: repository,
          mount: 'oidc',
          role: 'default',
          body: defaultRole,
          layout: layout,
        ).check(it.context),
        isA<Satisfied>(),
      );
    });

    test('a role body that is not an object is refused rather than sent', () async {
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answer(''));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: FakeFiles(<String, String>{profilePath: profile, credentials: credentialFile}),
        http: http,
        step: 'vault_auth_role',
      );

      final CheckResult result = await const VaultAuthRole(
        repository: repository,
        mount: 'oidc',
        role: 'default',
        body: 'user_claim=preferred_username groups_claim=groups',
        layout: layout,
      ).check(it.context);

      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('JSON object'));
    });
  });

  group('a field copied from the entry that owns it', () {
    // The hand-filled input with the variable present and unanswered, which is what a value that
    // comes from another entry rather than from a person looks like in that file.
    const String unfilledManagerSecret = 'MANAGER_OIDC_CLIENT_SECRET=\n';

    // The failure this exists for is a credential agreed between two sides. Minted twice it is two
    // values, and the side presenting one is not holding what the side that registered it expects —
    // a login that fails for a reason neither side reports. So it is minted ONCE, at the entry that
    // owns it, and the tier a workload reads gets an entry of its own holding that value alone.
    //
    // Two entries and not one shared, because the owning entry holds every client's secret together
    // and the policy a workload's reader logs in under permits its own tier and nothing else. One
    // entry read by everybody would let a workload read another workload's credential.
    const VaultKvEntry copying = VaultKvEntry(
      repository: repository,
      mount: 'secret',
      path: 'dev/app/manager',
      fields: <String>['oidc-client-secret=MANAGER_OIDC_CLIENT_SECRET'],
      mint: <String>[],
      fieldsOwnedElsewhere: <String>[],
      optionalFields: <String>['oidc-client-secret'],
      copyFrom: <String>['oidc-client-secret=dev/idp/bootstrap:controller-client-secret'],
      layout: layout,
      secrets: secretsPath,
    );

    /// A store whose owning entry holds [owned], and whose destination holds [destination].
    ScriptedHttp storeHolding({String? owned, String? destination}) =>
        ScriptedHttp((HttpRequest request, int nth) {
          if (request.method != 'GET') {
            return answer('');
          }
          final bool source = request.url.contains('idp/bootstrap');
          final String? held = source ? owned : destination;
          if (held == null) {
            return answer('', status: 404);
          }
          return answer(
            jsonEncode(<String, Object?>{
              'data': <String, Object?>{
                'data': <String, Object?>{
                  source ? 'controller-client-secret' : 'oidc-client-secret': held,
                },
              },
            }),
          );
        });

    test('the destination is written with the value the owner holds', () async {
      final ScriptedHttp http = storeHolding(owned: 'the-one-minted-value');
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith(unfilledManagerSecret),
        http: http,
      );

      await copying.apply(it.context);

      final Iterable<HttpRequest> writes = http.sent.where(
        (HttpRequest each) => each.method != 'GET',
      );
      expect(writes, isNotEmpty);
      expect(
        writes.last.body,
        contains('the-one-minted-value'),
        reason: 'copied and never minted again: two mints are two values, and only one is agreed',
      );
    });

    test('COUNTER-PROBE: an owner that holds nothing is a refusal, not a fresh value', () async {
      // Without this the step could quietly generate one, and the two sides would hold different
      // secrets while every step reported success.
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith(unfilledManagerSecret),
        http: storeHolding(),
      );

      await expectLater(copying.apply(it.context), throwsA(isA<StateError>()));
    });

    test('and the destination already holding it is finished', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith(unfilledManagerSecret),
        http: storeHolding(owned: 'the-one-minted-value', destination: 'the-one-minted-value'),
      );

      expect(await copying.check(it.context), isA<Satisfied>());
    });
  });
  group('a field written from an ANSWER of this run', () {
    // The case this exists for: the password that raises a command to root is something the run was
    // TOLD, not something a file on the machine holds — and putting it in the hand-filled file as
    // well would be the same value in two places, drifting apart the first time one is changed.
    const VaultKvEntry fromAnswer = VaultKvEntry(
      repository: repository,
      mount: 'secret',
      path: 'dev/machine/m1',
      fields: <String>[],
      fieldsFromAnswers: <String>['sudo-password=elevation_password'],
      mint: <String>[],
      fieldsOwnedElsewhere: <String>[],
      optionalFields: <String>[],
      copyFrom: <String>[],
      layout: layout,
      secrets: secretsPath,
    );

    ScriptedHttp absent() => ScriptedHttp(
      (HttpRequest request, int nth) =>
          request.method == 'GET' ? answer('', status: 404) : answer(''),
    );

    test('reaches the entry, and the value never came from a file', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith(''),
        http: absent(),
        answers: const Arguments(<String, Object>{
          'stage': 'dev',
          'elevation_password': 'what raises a command',
        }),
      );

      expect(await fromAnswer.check(it.context), isA<Ready>());

      final List<String> written = <String>[];
      final ({StepContext context, MemoryRecorder recorder}) writing = contextOf(
        files: machineWith(''),
        http: ScriptedHttp((HttpRequest request, int nth) {
          if (request.method != 'GET') {
            written.add(request.body ?? '');
          }
          return request.method == 'GET' ? answer('', status: 404) : answer('');
        }),
        answers: const Arguments(<String, Object>{
          'stage': 'dev',
          'elevation_password': 'what raises a command',
        }),
      );
      await fromAnswer.apply(writing.context);

      expect(written, hasLength(1));
      expect(written.single, contains('sudo-password'));
      expect(
        written.single,
        contains('what raises a command'),
        reason: 'the value the run was told is what has to reach the store',
      );
    });

    test('a run holding no such answer is refused, and the answer is named', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        files: machineWith(''),
        http: absent(),
      );

      final CheckResult judged = await fromAnswer.check(it.context);
      expect(judged, isA<Blocked>());
      expect((judged as Blocked).reason, contains('elevation_password'));
    });

    test(
      'a field written from BOTH a file and an answer is refused — one field holds one value',
      () async {
        const VaultKvEntry both = VaultKvEntry(
          repository: repository,
          mount: 'secret',
          path: 'dev/machine/m1',
          fields: <String>['sudo-password=SUDO_PASSWORD'],
          fieldsFromAnswers: <String>['sudo-password=elevation_password'],
          mint: <String>[],
          fieldsOwnedElsewhere: <String>[],
          optionalFields: <String>[],
          copyFrom: <String>[],
          layout: layout,
          secrets: secretsPath,
        );
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          files: machineWith('SUDO_PASSWORD=from-the-file\n'),
          http: absent(),
          answers: const Arguments(<String, Object>{
            'stage': 'dev',
            'elevation_password': 'from-the-run',
          }),
        );

        final CheckResult judged = await both.check(it.context);
        expect(judged, isA<Blocked>());
        expect((judged as Blocked).reason, contains('one field holds one value'));
      },
    );

    test(
      'THE INNOCENT NEIGHBOUR: a field an installation may not have is left out, not refused',
      () async {
        const VaultKvEntry optional = VaultKvEntry(
          repository: repository,
          mount: 'secret',
          path: 'dev/machine/m1',
          fields: <String>[],
          fieldsFromAnswers: <String>['sudo-password=elevation_password'],
          mint: <String>[],
          fieldsOwnedElsewhere: <String>[],
          optionalFields: <String>['sudo-password'],
          copyFrom: <String>[],
          layout: layout,
          secrets: secretsPath,
        );
        final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
          files: machineWith(''),
          http: absent(),
        );

        // Every field left out means nothing to write, which this step says rather than writing an
        // entry that replaces what is there with nothing.
        expect(await optional.check(it.context), isA<Satisfied>());
      },
    );
  });
}
