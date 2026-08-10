import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The steps that produce one Vault's quorum, and the file everything that reads from that Vault
/// ultimately depends on.
///
/// Every case here is an incident that happened: a placeholder written over a real quorum, an
/// unreadable answer read as "not initialized yet", a root token echoed into a log. The first group
/// is about where the connection comes from — the address out of the profile, the credential file
/// out of the stage answer — because a program file that carried either would ship one
/// installation's values to every installation.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentials = '$repository/secrets/vault-dev.txt';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';

  // One deployment's layout, stated the way its program rows state it. The package itself carries
  // no layout, so every step in this file is handed this one.
  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  /// The profile as the deployment writes it, naming [vaultUrl] as this installation's Vault.
  String profileNaming(String vaultUrl) => 'global:\n  vaultUrl: $vaultUrl\n';

  String credentialFileHolding(List<String> keys) =>
      renderCredentials(url: url, unsealKeys: keys, rootToken: token);

  /// A context wired through the recording ports, so a test can read what an operator would see.
  ({StepContext context, MemoryRecorder recorder}) contextOf({
    required FakeShell shell,
    required FakeFiles files,
    required Http http,
    String step = 'vault_init',
    Arguments answers = const Arguments(<String, Object>{'stage': 'dev'}),
  }) {
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final StepName name = StepName(step);
    return (
      context: StepContext(
        shell: RecordingShell(shell, recorder: recorder, redactor: Redactor.none, step: name),
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

  group('where the connection comes from', () {
    test('a checkout with no profile blocks, and no request is sent anywhere', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": true}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          credentials: credentialFileHolding(<String>['k1']),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      final CheckResult result = await const VaultUnsealed(
        repository: repository,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(profilePath));
      expect(result.reason, contains(layout.urlKey));
      expect(http.sent, isEmpty, reason: 'a step without an address must not reach for one');
    });

    test('a profile that does not carry the address blocks by file and key', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": true}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: 'global: {}\n',
          credentials: credentialFileHolding(<String>['k1']),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      final CheckResult result = await const VaultUnsealed(
        repository: repository,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains(profilePath));
      expect(result.reason, contains(layout.urlKey));
      expect(
        http.sent,
        isEmpty,
        reason:
            'a guessed address reaches a Vault that answers, and answers wrongly, and nothing '
            'reports that until a secret cannot be resolved',
      );
    });

    test('the address is read out of the profile, never composed from an answer', () async {
      // One cluster can point at another cluster's Vault, so no answer about THIS cluster could
      // yield the address — the profile is the only place the relationship is written down.
      const String remoteVault = 'https://vault.master.example.com';
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": false}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(remoteVault),
          credentials: credentialFileHolding(<String>['k1', 'k2', 'k3']),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      expect(
        await const VaultUnsealed(repository: repository, layout: layout).check(it.context),
        isA<Satisfied>(),
      );
      expect(http.sent.single.url, '$remoteVault/v1/sys/seal-status');
    });

    test('the credential file follows the stage answer', () async {
      // The name is composed from the stage, so a prod run reads vault-prod.txt — and the same
      // files under a dev answer are a missing credential file, which is what proves the stage
      // really travels rather than being the dev everybody tested with.
      final FakeFiles files = FakeFiles(<String, String>{
        profilePath: profileNaming(url),
        '$repository/secrets/vault-prod.txt': credentialFileHolding(<String>['k1', 'k2']),
      });
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": true}'),
      );

      final ({StepContext context, MemoryRecorder recorder}) prod = contextOf(
        shell: FakeShell(),
        files: files,
        http: http,
        step: 'vault_unsealed',
        answers: const Arguments(<String, Object>{'stage': 'prod'}),
      );
      expect(
        await const VaultUnsealed(repository: repository, layout: layout).check(prod.context),
        isA<Ready>(),
        reason: 'the quorum stands under the prod name and the store is sealed',
      );

      final ({StepContext context, MemoryRecorder recorder}) dev = contextOf(
        shell: FakeShell(),
        files: files,
        http: http,
        step: 'vault_unsealed',
      );
      final CheckResult wrongStage = await const VaultUnsealed(
        repository: repository,
        layout: layout,
      ).check(dev.context);
      expect(wrongStage, isA<Blocked>());
      expect((wrongStage as Blocked).reason, contains('vault-dev.txt'));
    });

    test('where the profile and the credential file stand is the row\'s to say', () async {
      // Another product keeps the same facts elsewhere: the profile under another name, the
      // address under other keys, the credential file in another directory. The layout arguments
      // carry all of it, and the stage answer still fills the marked stage in the moved path.
      const VaultLayout moved = VaultLayout(
        profile: 'platform/profile.yaml',
        urlKey: 'platform.vaultUrl',
        nameKey: 'platform.clusterName',
        authPathKey: 'platform.vaultKubernetesAuthPath',
        credentials: 'platform/vault-<stage>.txt',
        runAnswer: 'stage',
      );
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": false}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          '$repository/platform/profile.yaml': 'platform:\n  vaultUrl: $url\n',
          '$repository/platform/vault-dev.txt': credentialFileHolding(<String>['k1']),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      expect(
        await const VaultUnsealed(repository: repository, layout: moved).check(it.context),
        isA<Satisfied>(),
      );
      expect(http.sent.single.url, '$url/v1/sys/seal-status');
    });

    test('a moved profile that lacks the address names the configured key', () async {
      const VaultLayout moved = VaultLayout(
        profile: 'platform/profile.yaml',
        urlKey: 'platform.vaultUrl',
        nameKey: 'platform.clusterName',
        authPathKey: 'platform.vaultKubernetesAuthPath',
        credentials: 'platform/vault-<stage>.txt',
        runAnswer: 'stage',
      );
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) => answer('{}'));
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{'$repository/platform/profile.yaml': 'platform: {}\n'}),
        http: http,
        step: 'vault_unsealed',
      );

      final CheckResult result = await const VaultUnsealed(
        repository: repository,
        layout: moved,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('$repository/platform/profile.yaml'));
      expect(result.reason, contains('platform.vaultUrl'));
      expect(http.sent, isEmpty);
    });
  });

  group('minting the quorum', () {
    test('writes the credential file and never says what is in it', () async {
      final FakeFiles files = FakeFiles(<String, String>{profilePath: profileNaming(url)});
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) {
        if (request.url.endsWith('/v1/sys/init') && request.method == 'GET') {
          return answer('{"initialized": false}');
        }
        return answer(
          jsonEncode(<String, Object?>{
            'keys_base64': <String>['k1', 'k2', 'k3', 'k4', 'k5'],
            'root_token': token,
          }),
        );
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: files,
        http: http,
      );

      const VaultInit step = VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      );
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      expect(files.contents[credentials], contains(token));
      expect(unsealKeysIn(files.contents[credentials] ?? ''), hasLength(5));
      expect(files.modes[credentials], 0x180, reason: 'the file holds the keys to everything');

      // The whole record, as the operator reads it and as an exported run is pasted into a message.
      final String record = it.recorder.events
          .map((RunEvent event) => jsonEncode(const RecordCodec().event(event)))
          .join('\n');
      expect(
        record,
        isNot(contains(token)),
        reason: 'the record carries the pointer to the file and never the value in it',
      );
      for (final String key in <String>['k1', 'k2', 'k3', 'k4', 'k5']) {
        expect(record, isNot(contains('"$key"')));
      }
      expect(it.recorder.logLines.join('\n'), contains(credentials));
      expect(it.recorder.logLines.join('\n').toUpperCase(), contains('COPY'));
    });

    test('a second run has nothing to do', () async {
      final FakeFiles files = FakeFiles(<String, String>{
        profilePath: profileNaming(url),
        credentials: credentialFileHolding(<String>['k1', 'k2', 'k3']),
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: files,
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"initialized": true}')),
      );

      expect(
        await const VaultInit(
          repository: repository,
          keyShares: 5,
          keyThreshold: 3,
          layout: layout,
        ).check(it.context),
        isA<Satisfied>(),
      );
      expect(files.written, isEmpty);
    });

    test('an answer that cannot be read is not proof of an uninitialized store', () async {
      // The expensive one. The reading transiently returns nothing on a store that IS initialized,
      // and reading that as "not yet" mints a second quorum over the storage of the first.
      final FakeFiles files = FakeFiles(<String, String>{profilePath: profileNaming(url)});
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: files,
        http: ScriptedHttp((HttpRequest request, int nth) => answer('')),
      );

      final CheckResult result = await const VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('second quorum'));
    });

    test('a store that says it is uninitialized while a quorum is on disk is refused', () async {
      final FakeFiles files = FakeFiles(<String, String>{
        profilePath: profileNaming(url),
        credentials: credentialFileHolding(<String>['k1', 'k2', 'k3']),
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: files,
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"initialized": false}')),
      );

      final CheckResult result = await const VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('disagree'));
      expect(files.written, isEmpty, reason: 'the only copy of the quorum is never written over');
    });

    test('an initialized store with no credential file names the escrow', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{profilePath: profileNaming(url)}),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"initialized": true}')),
      );

      final CheckResult result = await const VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('escrow'));
    });

    test('a credential file that came back through a windows editor is refused', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1']).replaceAll('\n', '\r\n'),
        }),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"initialized": true}')),
      );

      final CheckResult result = await const VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('carriage return'));
    });

    test('it cannot be minted twice, and says why', () {
      const VaultInit step = VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      );
      expect(step.irreversibleReason, contains('destroying'));
      expect(step.irreversibleReason, isNot(contains('not implemented')));
    });
  });

  group('feeding the quorum back', () {
    test('one key at a time, and it stops the moment the store serves', () async {
      // Feeding a fixed number blind spends keys that were not needed and hides which one was
      // rejected. Three of five is the threshold here, so two keys must never be offered.
      int offered = 0;
      final ScriptedHttp http = ScriptedHttp((HttpRequest request, int nth) {
        if (request.method == 'GET') {
          return answer('{"sealed": true}');
        }
        offered += 1;
        return answer('{"sealed": ${offered < 3}}');
      });
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1', 'k2', 'k3', 'k4', 'k5']),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      const VaultUnsealed step = VaultUnsealed(repository: repository, layout: layout);
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      expect(offered, 3, reason: 'the seal state is read again after every key');
      expect(it.recorder.logLines.join('\n'), contains('after 3 of 5 keys'));
      final String record = it.recorder.events
          .map((RunEvent event) => jsonEncode(const RecordCodec().event(event)))
          .join('\n');
      expect(
        record,
        isNot(contains('"k1"')),
        reason: 'a key travels in a body and not in the record',
      );
    });

    test('a store that already serves is nothing to do', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1', 'k2', 'k3']),
        }),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('{"sealed": false}')),
        step: 'vault_unsealed',
      );

      expect(
        await const VaultUnsealed(repository: repository, layout: layout).check(it.context),
        isA<Satisfied>(),
      );
    });

    test('a credential file with carriage returns is refused before a key is offered', () async {
      // The symptom without this guard: every key refused, on every attempt, forever, with nothing
      // in the journal naming the cause.
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"sealed": true}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1']).replaceAll('\n', '\r\n'),
        }),
        http: http,
        step: 'vault_unsealed',
      );

      final CheckResult result = await const VaultUnsealed(
        repository: repository,
        layout: layout,
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('carriage return'));
      expect(http.sent.where((HttpRequest r) => r.method != 'GET'), isEmpty);
    });
  });

  group('the requests this area sends', () {
    test('everything that reads is a GET, and a dry run would let it through', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"initialized": true, "sealed": false}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1', 'k2', 'k3']),
        }),
        http: http,
      );

      await const VaultInit(
        repository: repository,
        keyShares: 5,
        keyThreshold: 3,
        layout: layout,
      ).check(it.context);
      await const VaultUnsealed(repository: repository, layout: layout).check(it.context);
      await const VaultKvMount(
        repository: repository,
        path: 'secret',
        layout: layout,
      ).check(it.context);

      expect(http.sent, isNotEmpty);
      for (final HttpRequest request in http.sent) {
        expect(request.method, 'GET', reason: 'a check only looks');
        expect(request.observes, isTrue);
      }
    });

    test('the token rides the one header the redactor removes by name', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) => answer('{"data": {}}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profileNaming(url),
          credentials: credentialFileHolding(<String>['k1']),
        }),
        http: http,
      );

      await const VaultPolicy(
        repository: repository,
        name: 'admin',
        rules: 'path "*" { capabilities = ["sudo"] }',
        layout: layout,
      ).check(it.context);

      final HttpRequest carrying = http.sent.firstWhere(
        (HttpRequest request) => request.headers.isNotEmpty,
      );
      expect(carrying.headers.keys, contains('authorization'));
      expect(carrying.headers['authorization'], contains(token));
      expect(
        Redactor.none.hideHeaders(carrying.headers)['authorization'],
        Redactor.marker,
        reason:
            'the header is chosen for this: the value is removed on its name alone, so the token '
            'cannot reach the record even on a run where nobody registered it as a secret',
      );
    });
  });
}

HttpAnswer answer(String body, {int status = 200}) => HttpAnswer(
  status: status,
  body: body,
  headers: const <String, String>{},
  elapsed: Duration.zero,
);

/// A network port whose answer may depend on how many times the same request was already sent.
///
/// The table-driven fake answers the same thing every time, which cannot express the one property
/// the unseal step exists for: the state changes while the step is running, and the step has to
/// notice and stop.
final class ScriptedHttp implements Http {
  ScriptedHttp(this._answer);

  final HttpAnswer Function(HttpRequest request, int nth) _answer;

  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    final int nth = sent
        .where((HttpRequest each) => each.method == request.method && each.url == request.url)
        .length;
    sent.add(request);
    return _answer(request, nth);
  }
}
