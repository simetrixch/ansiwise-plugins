import 'dart:convert';
import 'dart:typed_data';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The entry a row could not fill: an ed25519 key pair and the fingerprint of this host's key.
///
/// **What every assertion here is about is the ENTRY, never the verdict.** A step of this kind can
/// answer `Satisfied` and have written a second key pair over the one a running caller uses, and a
/// probe that read the verdict would call that a pass. So each case below reads what stands in the
/// store afterwards, and the two that matter most read the SAME value twice — before and after a
/// second run.
///
/// **The known answers come from outside this repository.** The public key the first case expects is
/// the one RFC 8032 states for that seed, and the fingerprint the host key case expects is what
/// `ssh-keygen -lf` prints for that file. Neither was produced by this code, so neither moves with
/// it: an error in the curve arithmetic or in the digest turns them red rather than being copied
/// into the expectation.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String credentialsPath = '$repository/secrets/vault-dev.txt';
  const String hostKeyPath = '/etc/ssh/ssh_host_ed25519_key.pub';
  const String url = 'https://vault.m1.example.com';
  const String token = 'hvs.ThisIsNotARealRootTokenItIsATestFixture';

  // A real key pair made for this file, of which only the public half is here. Its fingerprint is
  // what `ssh-keygen -lf` prints for it, taken from that command and not from this code.
  const String hostPublicKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMKvTYh8dMzcOvxxL6k7oJ9LIO8v8JIHpCn8i3GVHo3z '
      'root@probe-host';
  const String hostFingerprint = 'SHA256:9QOJ4nSY1s26z3gj6aQH9hMKC8otFmd9J+RX4lrOcGQ';

  // What the fake source of unpredictability makes on its first two draws, and therefore the one
  // pair every case below mints. The comment is the row's, with the cluster's own name filled in.
  const String mintedPublicKey =
      'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIO+2B7di7Fis1nNg+vIzqOm4MK0ArFbkgJzW638kUa0 '
      'ansiwise@m1';

  const VaultLayout layout = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
  );

  const VaultKvSshKeyPair step = VaultKvSshKeyPair(
    repository: repository,
    mount: 'secret',
    path: '<stage>/manager-host/ssh',
    privateKeyField: 'ssh-private-key',
    hostKeyFingerprintField: 'host-key-fp',
    hostKeyPath: hostKeyPath,
    comment: 'ansiwise@<cluster>',
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

  ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy}) contextOver(
    _Store store, {
    String hostKey = hostPublicKey,
    bool hostKeyIsThere = true,
  }) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    final FakeEntropy entropy = FakeEntropy();
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{
          profilePath: profile,
          credentialsPath: credentialFile,
          if (hostKeyIsThere) hostKeyPath: '$hostKey\n',
        }),
        http: store,
        clock: FakeClock(),
        entropy: entropy,
        log: const _SilentLog(),
        step: const StepName('vault_kv_ssh_key_pair'),
        arguments: Arguments.none,
        answers: const Arguments(<String, Object>{'stage': 'dev'}),
        facts: Facts.none,
        measurements: _Sink(published),
      ),
      published: published,
      entropy: entropy,
    );
  }

  group('an entry that carries nothing yet', () {
    test('the check says there is work to do and publishes nothing', () async {
      final _Store store = _Store();
      final ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy})
      it = contextOver(store);

      expect(await step.check(it.context), isA<Ready>());
      expect(it.published, isEmpty);
    });

    test('the apply writes a key pair and the fingerprint of THIS host, and both are read back '
        'afterwards', () async {
      final _Store store = _Store();
      final ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy})
      it = contextOver(store);

      await step.apply(it.context);

      // The ENTRY, field by field. A verdict would say nothing about what a caller will read.
      final Object? written = store.held?['ssh-private-key'];
      expect(written, isA<String>());
      expect(written! as String, startsWith(sshPrivateKeyOpening));
      expect(sshPublicKeyIn(written as String), mintedPublicKey);
      expect(store.held?['host-key-fp'], hostFingerprint);

      // The postcondition the engine asks for after every apply.
      expect(await step.check(it.context), isA<Satisfied>());
      expect(it.published[const MeasurementName('ssh_public_key')], mintedPublicKey);
    });
  });

  group('an entry that already holds a key pair', () {
    test('THE DEFECT THIS STEP IS BUILT AGAINST: a second run keeps the pair it found', () async {
      // Minting again would leave the caller presenting a key that stands in no authorized_keys
      // file anywhere, and nothing in this run knows which machines carry the old one.
      final _Store store = _Store();
      await step.apply(contextOver(store).context);
      final String first = store.held!['ssh-private-key']! as String;

      final ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy})
      again = contextOver(store);
      expect(await step.check(again.context), isA<Satisfied>());
      await step.apply(again.context);

      expect(store.held?['ssh-private-key'], first);
      expect(again.published[const MeasurementName('ssh_public_key')], mintedPublicKey);
      expect(
        again.entropy.drawn,
        0,
        reason: 'a second run that drew from the source of unpredictability made a second key pair',
      );
    });

    test('a fingerprint naming another host is replaced, and the key beside it is not', () async {
      final _Store store = _Store();
      await step.apply(contextOver(store).context);
      final String first = store.held!['ssh-private-key']! as String;
      store.held!['host-key-fp'] = 'SHA256:ThisIsTheFingerprintOfAMachineThatWasReinstalled';

      final ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy})
      again = contextOver(store);
      expect(await step.check(again.context), isA<Ready>());
      await step.apply(again.context);

      expect(store.held?['host-key-fp'], hostFingerprint);
      expect(store.held?['ssh-private-key'], first);
    });

    test('an entry holding the key and no fingerprint at all is half-written, not done', () async {
      final _Store store = _Store();
      await step.apply(contextOver(store).context);
      store.held!.remove('host-key-fp');

      expect(await step.check(contextOver(store).context), isA<Ready>());
    });
  });

  group('what must never be written over', () {
    test('a private key this cannot read blocks the run instead of being replaced', () async {
      final _Store store = _Store(
        holding: <String, Object?>{
          'ssh-private-key': 'not a key at all',
          'host-key-fp': hostFingerprint,
        },
      );

      final CheckResult answer = await step.check(contextOver(store).context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('ssh-private-key'));
    });

    test('and its apply refuses too, so nothing at all reaches the store', () async {
      final _Store store = _Store(
        holding: <String, Object?>{'ssh-private-key': 'not a key at all'},
      );

      await expectLater(step.apply(contextOver(store).context), throwsA(isA<StateError>()));
      expect(store.held?['ssh-private-key'], 'not a key at all');
      expect(store.wrote, isEmpty);
    });

    test('a write the store refuses is a failure and not a run that quietly did nothing', () async {
      final _Store store = _Store(writeStatus: 403);

      await expectLater(step.apply(contextOver(store).context), throwsA(isA<RequestRefused>()));
      expect(store.held, isNull);
    });

    test('a read that FAILED is not an entry that holds nothing', () async {
      // A 403 answers neither what the entry holds nor that it holds nothing. Read as work to do,
      // it sends the run into an apply that mints over a key pair somebody is using.
      final _Store store = _Store(readStatus: 403);

      final CheckResult answer = await step.check(contextOver(store).context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('403'));
    });
  });

  group('the host key this machine presents', () {
    test('a file that is not there blocks the run and publishes nothing', () async {
      final _Store store = _Store();
      final ({StepContext context, Map<MeasurementName, String> published, FakeEntropy entropy})
      it = contextOver(store, hostKeyIsThere: false);

      final CheckResult answer = await step.check(it.context);
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains(hostKeyPath));
      expect(it.published, isEmpty);
    });

    test(
      'a file that is not a public key line blocks rather than fingerprinting the text',
      () async {
        final _Store store = _Store();
        final CheckResult answer = await step.check(
          contextOver(store, hostKey: 'this is not a key').context,
        );

        expect(answer, isA<Blocked>());
        expect((answer as Blocked).reason, contains(hostKeyPath));
      },
    );
  });

  group('THE INNOCENT NEIGHBOURS', () {
    test('a field another writer owns is written back exactly as it stood', () async {
      // A write to this store replaces the whole entry. Composing one out of the two fields this
      // step owns would delete everything else the entry carries, silently and for good.
      final _Store store = _Store(holding: <String, Object?>{'kept-by-somebody-else': 'a value'});

      await step.apply(contextOver(store).context);

      expect(store.held?['kept-by-somebody-else'], 'a value');
      expect(store.held?['ssh-private-key'], isA<String>());
    });

    test('an entry that is complete and current asks for no work', () async {
      final _Store store = _Store();
      await step.apply(contextOver(store).context);
      final int writes = store.wrote.length;

      expect(await step.check(contextOver(store).context), isA<Satisfied>());
      expect(store.wrote.length, writes, reason: 'a check that writes is not a check');
    });
  });

  group('the key format, against answers made outside this repository', () {
    test('RFC 8032 test 1: the seed grows into the public key that document states', () async {
      final SshKeyPair pair = await mintedSshKeyPair(
        seed: '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60',
        check: '00000000',
        comment: '',
      );

      // d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a, as the blob carries it.
      expect(
        pair.publicKey,
        'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea',
      );
    });

    test('the public half read back out of a container is the one that was minted, comment and '
        'all', () async {
      // A comment of a different length pushes the private section onto another padding, which is
      // the part of the format a reader counts rather than skips.
      for (final String comment in <String>['', 'a', 'ansiwise@m1', 'a rather longer comment']) {
        final SshKeyPair pair = await mintedSshKeyPair(
          seed: 'fa4e000100000000000000000000000000000000000000000000000000000000',
          check: 'fa4e0002',
          comment: comment,
        );
        expect(sshPublicKeyIn(pair.privateKey), pair.publicKey, reason: 'comment "$comment"');
      }
    });

    test('the fingerprint is the one ssh-keygen prints for that same file', () {
      expect(sshFingerprintOf(hostPublicKey), hostFingerprint);
    });

    test('THE PLANTED DEFECT: a container whose two public halves disagree is refused', () async {
      final SshKeyPair pair = await mintedSshKeyPair(
        seed: 'fa4e000100000000000000000000000000000000000000000000000000000000',
        check: 'fa4e0002',
        comment: 'ansiwise@m1',
      );

      expect(
        sshPublicKeyIn(_publicHalfBent(pair)),
        isNull,
        reason:
            'a container whose halves do not match is not a key pair, and the public one read '
            'off the front of it would log in nowhere',
      );
    });

    test('THE INNOCENT NEIGHBOUR: a public key line of another algorithm is fingerprinted too', () {
      // This reads a public key line and not an ed25519 one. Which host key a caller compares
      // against is the caller's business, and refusing the others here would decide it from a
      // package that has no way of knowing.
      expect(
        sshFingerprintOf(
          'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQDPd1uS1Ftt8CkFHUdVpDRJ9K/3TQXFA7yjs5tMLLLnRcYS'
          'Wt7Q9tPCOUZThjJ7lyOAWDvFtaJTbMOWiXvBbTMWOUvPd5CGrEytJPVNo7bxi8g8xJ3Ss0YyzJZoLKGnZLpq'
          'z6yeXBIMU39mJUKvBH2QZOFT8N71Bq3s0T2dY0OoWQ== somebody@somewhere',
        ),
        startsWith('SHA256:'),
      );
    });

    test('a line whose base64 does not begin with the algorithm it names is refused', () {
      // A truncated or rewritten file otherwise yields a fingerprint that looks entirely plausible
      // and matches no host on earth.
      expect(sshFingerprintOf('ssh-ed25519 ${base64.encode(utf8.encode('not a blob'))}'), isNull);
      expect(sshFingerprintOf('ssh-ed25519'), isNull);
      expect(sshFingerprintOf(''), isNull);
    });
  });
}

/// [pair]'s container with the copy of the public key inside its private field bent by one byte.
///
/// The container writes the public key three times — in the outer blob, in the private section, and
/// at the tail of the private field. The last of those is the one that says the two halves belong
/// together, so that is the copy this bends.
String _publicHalfBent(SshKeyPair pair) {
  final Uint8List public = base64.decode(pair.publicKey.split(' ')[1]);
  final Uint8List key = Uint8List.sublistView(public, public.length - 32);
  final List<String> lines = const LineSplitter().convert(pair.privateKey);
  final Uint8List container = base64.decode(
    lines.where((String line) => !line.startsWith('-----')).join(),
  );

  int at = -1;
  for (int i = 0; i + key.length <= container.length; i++) {
    bool same = true;
    for (int j = 0; j < key.length; j++) {
      if (container[i + j] != key[j]) {
        same = false;
        break;
      }
    }
    if (same) {
      at = i;
    }
  }
  container[at] = container[at] ^ 0xff;
  return '$sshPrivateKeyOpening\n${base64.encode(container)}\n$sshPrivateKeyClosing\n';
}

/// The store, as far as this step meets it: an entry that a write really changes.
///
/// A table-driven fake answers the same thing however often it is asked, which cannot express the
/// property every case here turns on — that a second run reads what the first one wrote.
final class _Store implements Http {
  _Store({Map<String, Object?>? holding, this.readStatus = 200, this.writeStatus = 200})
    : held = holding == null ? null : <String, Object?>{...holding};

  /// What the entry holds, or null where nothing was ever written to it.
  Map<String, Object?>? held;

  /// What a read answers, for the case where reading fails rather than finding nothing.
  final int readStatus;

  /// What a write answers.
  final int writeStatus;

  /// Every write that was sent, so a probe can say a check wrote nothing.
  final List<String> wrote = <String>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    if (request.method == 'GET') {
      if (readStatus != 200) {
        return _answer('{"errors":["permission denied"]}', status: readStatus);
      }
      return held == null
          ? _answer('', status: 404)
          : _answer(
              jsonEncode(<String, Object?>{
                'data': <String, Object?>{'data': held, 'metadata': <String, Object?>{}},
              }),
            );
    }
    wrote.add('${request.method} ${request.url}');
    if (writeStatus != 200) {
      return _answer('{"errors":["refused"]}', status: writeStatus);
    }
    final Object? body = jsonDecode(request.body ?? '{}');
    final Object? data = body is Map<String, Object?> ? body['data'] : null;
    held = data is Map<String, Object?> ? <String, Object?>{...data} : <String, Object?>{};
    return _answer('{}');
  }

  static HttpAnswer _answer(String body, {int status = 200}) => HttpAnswer(
    status: status,
    body: body,
    headers: const <String, String>{},
    elapsed: Duration.zero,
  );
}

/// A log nothing reads, so a probe measures what a step DID and not what it said about it.
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

/// Collects what a step publishes, so a probe can read it.
final class _Sink implements MeasurementSink {
  const _Sink(this._into);

  final Map<MeasurementName, String> _into;

  @override
  void publish(MeasurementName name, String value) => _into[name] = value;
}
