import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

import 'dkim_fixture.dart';

/// The public half read out of a private key, against an answer made outside this repository.
void main() {
  group('the public half of an RSA private key', () {
    test('the PKCS#8 container openssl writes yields the p= value openssl prints', () {
      expect(dkimPublicKeyIn(pkcs8Fixture), publicKeyFixture);
    });

    test('the PKCS#1 container yields the same value, because it is the same key', () {
      expect(dkimPublicKeyIn(pkcs1Fixture), publicKeyFixture);
    });

    test('a trailing newline or none, and surrounding blank lines, read the same', () {
      expect(dkimPublicKeyIn(pkcs8Fixture.trim()), publicKeyFixture);
      expect(dkimPublicKeyIn('\n\n$pkcs8Fixture\n\n'), publicKeyFixture);
    });
  });

  group('what is refused as unreadable', () {
    test('a key of another algorithm in the same container is not an RSA key', () {
      expect(dkimPublicKeyIn(ed25519Fixture), isNull);
    });

    test('text that is not a container at all', () {
      expect(dkimPublicKeyIn(''), isNull);
      expect(dkimPublicKeyIn('not a key at all'), isNull);
      expect(dkimPublicKeyIn('-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n'), isNull);
    });

    test('a container whose bytes are not base64', () {
      expect(
        dkimPublicKeyIn('-----BEGIN PRIVATE KEY-----\n!!not base64!!\n-----END PRIVATE KEY-----\n'),
        isNull,
      );
    });

    test('a container cut short is not a key', () {
      final List<String> lines = pkcs8Fixture.trim().split('\n');
      final String truncated = <String>[
        lines.first,
        ...lines.sublist(1, lines.length ~/ 2),
        lines.last,
      ].join('\n');
      expect(dkimPublicKeyIn(truncated), isNull);
    });

    test('a container whose markers do not match each other', () {
      final String mixed = pkcs8Fixture.replaceFirst(rsaPrivateKeyClosing, pkcs1PrivateKeyClosing);
      expect(dkimPublicKeyIn(mixed), isNull);
    });
  });
}
