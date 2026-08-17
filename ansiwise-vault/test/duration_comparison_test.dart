/// A duration is one value with two spellings, and Vault answers in the other one.
///
/// The failure this exists for does not look like a failure. A role written with `"ttl":"24h"` comes
/// back from Vault holding `86400`; a comparison of the rendered forms calls that a difference, the
/// step writes the role again, asks again, and gets the same answer. It never converges — the same
/// role is rewritten on every run and reported as never right, on a Vault that is doing exactly what
/// it was told.
///
/// Measured on a real machine on 2026-08-17: the role step stopped a run partway through, with
/// Vault holding precisely the value the row had just written.
library;

import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

void main() {
  group('a duration against the seconds Vault answers with', () {
    test('24h is the 86400 Vault holds', () {
      expect(sameJsonValue(86400, '24h'), isTrue);
      expect(sameJsonValue('24h', 86400), isTrue);
    });

    test('the pieces add up, in the spelling Vault takes', () {
      expect(sameJsonValue(5400, '1h30m'), isTrue);
      expect(sameJsonValue(604800, '7d'), isTrue);
      expect(sameJsonValue(30, '30s'), isTrue);
    });

    test('COUNTER-PROBE: a duration that is NOT the same is still a difference', () {
      // Without this the comparison could answer true for everything and every test above would
      // pass while the step stopped noticing a role somebody changed.
      expect(sameJsonValue(86400, '12h'), isFalse);
      expect(sameJsonValue(3600, '1h1s'), isFalse);
    });

    test('COUNTER-PROBE: two texts stay two texts', () {
      // Only a number against a text can be one value written twice. Two texts are two values, and
      // reading both as durations would make "24h" and "1440m" interchangeable in a field where
      // Vault keeps them apart.
      expect(sameJsonValue('24h', '1440m'), isFalse);
    });

    test('COUNTER-PROBE: a text that is not a duration is left alone', () {
      expect(sameJsonValue(86400, 'twenty-four hours'), isFalse);
      expect(sameJsonValue(86400, '24 h'), isFalse);
      expect(sameJsonValue(86400, '24hours'), isFalse);
      expect(sameJsonValue(0, ''), isFalse);
    });

    test('and everything that is not a duration compares as it did before', () {
      expect(sameJsonValue('default', 'default'), isTrue);
      expect(sameJsonValue(<String>['a', 'b'], <String>['b', 'a']), isTrue);
      expect(sameJsonValue(<String>['a'], <String>['b']), isFalse);
      expect(sameJsonValue(0, 0), isTrue);
      expect(sameJsonValue(true, 'true'), isFalse);
    });
  });
}
