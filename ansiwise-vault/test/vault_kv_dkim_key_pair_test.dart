import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

import 'dkim_fixture.dart';
import 'support/store.dart';

/// The entry a row could not fill: the mail signing key pair, both halves.
///
/// **What every assertion here is about is the ENTRY, never the verdict.** A step of this kind can
/// answer `Satisfied` and have written a second key pair over the one the signer uses, and a probe
/// that read the verdict would call that a pass. So each case below reads what stands in the store
/// afterwards, and the one that matters most reads the SAME value twice — before and after a second
/// run.
///
/// **The pair is made by the machine's openssl**, so the shell is scripted to answer the minting
/// command with a key made outside this repository, and the public half every case expects is the
/// one openssl printed for that key.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentialsPath = '$repository/secrets/vault-dev.txt';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';
  const String privateField = 'dkim-private-key';
  const String publicField = 'dkim-public-key';
  final String minting = VaultKvDkimKeyPair.mintingArgv.join(' ');

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  const VaultKvDkimKeyPair step = VaultKvDkimKeyPair(
    repository: repository,
    mount: 'secret',
    path: '<stage>/app/relay',
    privateKeyField: privateField,
    publicKeyField: publicField,
    layout: layout,
  );

  const String profile =
      'global:\n'
      '  vaultUrl: $url\n'
      '  clusterName: m1\n'
      '  vaultKubernetesAuthPath: kubernetes-m1\n';

  final String credentialFile = renderCredentials(
    url: url,
    unsealKeys: const <String>['k1', 'k2', 'k3'],
    rootToken: token,
  );

  ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) contextOver(
    FakeStore store, {
    bool opensslAnswers = true,
  }) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    final FakeShell shell = FakeShell();
    if (opensslAnswers) {
      shell.answers(minting, pkcs8Fixture);
    } else {
      shell.fails(minting, exitCode: 1, stderr: 'genpkey: unknown algorithm');
    }
    return (
      context: StepContext(
        shell: shell,
        files: FakeFiles(<String, String>{profilePath: profile, credentialsPath: credentialFile}),
        http: store,
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const SilentLog(),
        step: const StepName('vault_kv_dkim_key_pair'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'stage': 'dev'}),
        facts: Facts.none,
        measurements: RecordingSink(published),
      ),
      published: published,
      shell: shell,
    );
  }

  group('an entry that carries nothing yet', () {
    test('the check says there is work to do and publishes nothing', () async {
      final FakeStore store = FakeStore();
      final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) it =
          contextOver(store);

      expect(await step.check(it.context), isA<Ready>());
      expect(it.published, isEmpty);
      expect(it.shell.ran, isEmpty, reason: 'a check that mints is not a check');
    });

    test('the apply mints a pair with openssl and writes BOTH halves, the public one read out of '
        'the private one', () async {
      final FakeStore store = FakeStore();
      final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) it =
          contextOver(store);

      await step.apply(it.context);

      // The ENTRY, field by field. A verdict would say nothing about what a signer will read.
      expect(store.held?[privateField], pkcs8Fixture);
      expect(store.held?[publicField], publicKeyFixture);
      expect(it.shell.ran, <String>[minting]);
      // What openssl answers is a private key, and it must not reach the record.
      expect(it.shell.commands.single.secretOutput, isTrue);

      // The postcondition the engine asks for after every apply.
      expect(await step.check(it.context), isA<Satisfied>());
      expect(it.published[const MeasurementName('dkim_public_key')], publicKeyFixture);
    });

    test('openssl failing is a failure, and nothing reaches the store', () async {
      final FakeStore store = FakeStore();
      final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) it =
          contextOver(store, opensslAnswers: false);

      await expectLater(step.apply(it.context), throwsA(isA<CommandFailed>()));
      expect(store.held, isNull);
    });

    test(
      'openssl answering with something that is not a key is refused before the write',
      () async {
        final FakeStore store = FakeStore();
        final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) it =
            contextOver(store);
        it.shell.answers(minting, 'unable to load key');

        await expectLater(step.apply(it.context), throwsA(isA<StateError>()));
        expect(store.held, isNull);
      },
    );
  });

  group('an entry that already holds a key pair', () {
    test('THE DEFECT THIS STEP IS BUILT AGAINST: a second run keeps the pair it found', () async {
      // Minting again would leave every record published for the first key naming one the signer
      // no longer holds, and nothing in this run knows which domains carry that record.
      final FakeStore store = FakeStore();
      await step.apply(contextOver(store).context);
      final String first = store.held![privateField]! as String;

      final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) again =
          contextOver(store);
      expect(await step.check(again.context), isA<Satisfied>());
      await step.apply(again.context);

      expect(store.held?[privateField], first);
      expect(store.held?[publicField], publicKeyFixture);
      expect(again.published[const MeasurementName('dkim_public_key')], publicKeyFixture);
      expect(again.shell.ran, isEmpty, reason: 'a second run that ran openssl made a second pair');
    });

    test('a private half without its public one is half-written: the public half is read out of '
        'it and the private one is not touched', () async {
      final FakeStore store = FakeStore(holding: <String, Object?>{privateField: pkcs1Fixture});
      final ({StepContext context, Map<MeasurementName, String> published, FakeShell shell}) it =
          contextOver(store);

      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      expect(store.held?[privateField], pkcs1Fixture);
      expect(store.held?[publicField], publicKeyFixture);
      expect(it.shell.ran, isEmpty);
    });

    test('a public half that is not the private one\'s is replaced by the one that is', () async {
      final FakeStore store = FakeStore(
        holding: <String, Object?>{privateField: pkcs8Fixture, publicField: 'AAAA'},
      );

      expect(await step.check(contextOver(store).context), isA<Ready>());
      await step.apply(contextOver(store).context);

      expect(store.held?[publicField], publicKeyFixture);
      expect(store.held?[privateField], pkcs8Fixture);
    });
  });

  group('what must never be written over', () {
    test('a private key this cannot read blocks the run instead of being replaced', () async {
      final FakeStore store = FakeStore(
        holding: <String, Object?>{privateField: 'not a key at all'},
      );

      final CheckResult answer = await step.check(contextOver(store).context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(privateField));
    });

    test('and its apply refuses too, so nothing at all reaches the store', () async {
      final FakeStore store = FakeStore(holding: <String, Object?>{privateField: ed25519Fixture});

      await expectLater(step.apply(contextOver(store).context), throwsA(isA<StateError>()));
      expect(store.held?[privateField], ed25519Fixture);
      expect(store.wrote, isEmpty);
    });

    test('a write the store refuses is a failure and not a run that quietly did nothing', () async {
      final FakeStore store = FakeStore(writeStatus: 403);

      await expectLater(step.apply(contextOver(store).context), throwsA(isA<RequestRefused>()));
      expect(store.held, isNull);
    });

    test('a read that FAILED is not an entry that holds nothing', () async {
      // A 403 answers neither what the entry holds nor that it holds nothing. Read as work to do,
      // it sends the run into an apply that mints over a key pair the signer is using.
      final FakeStore store = FakeStore(readStatus: 403);

      final CheckResult answer = await step.check(contextOver(store).context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('403'));
    });
  });

  group('THE INNOCENT NEIGHBOURS', () {
    test('a field another writer owns is written back exactly as it stood', () async {
      // A write to this store replaces the whole entry. Composing one out of the two fields this
      // step owns would delete everything else the entry carries, silently and for good.
      final FakeStore store = FakeStore(
        holding: <String, Object?>{'kept-by-somebody-else': 'a value'},
      );

      await step.apply(contextOver(store).context);

      expect(store.held?['kept-by-somebody-else'], 'a value');
      expect(store.held?[privateField], pkcs8Fixture);
    });

    test('an entry that is complete asks for no work', () async {
      final FakeStore store = FakeStore();
      await step.apply(contextOver(store).context);
      final int writes = store.wrote.length;

      expect(await step.check(contextOver(store).context), isA<Satisfied>());
      expect(store.wrote.length, writes, reason: 'a check that writes is not a check');
    });

    test('the plan names the two fields and the entry, and no value', () async {
      final StepPlan plan = await step.plan(contextOver(FakeStore()).context);
      expect(plan, isA<RequestPlan>());
      final RequestPlan request = plan as RequestPlan;
      expect(request.url, '$url/v1/secret/data/dev/app/relay');
      expect(request.body, contains(privateField));
      expect(request.body, contains(publicField));
      expect(request.body, isNot(contains('MIIE')));
    });
  });
}
