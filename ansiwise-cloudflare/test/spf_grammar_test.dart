import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';
import 'package:test/test.dart';

/// The pure SPF surgery the merge step rests on.
///
/// Every case here is the anatomy of one expensive mistake. A merge that loses another service's
/// `include:` takes that service's mail down; one that loses the qualifier of the all-mechanism
/// rewrites the domain's policy; one that matches an address inside a longer one authorises a
/// machine nobody meant. The functions are pure so each of those can be pinned without a network.
void main() {
  const String address = '203.0.113.25';

  group('recognising SPF', () {
    test('the version term is the exact word, alone or followed by mechanisms', () {
      expect(isSpfContent('v=spf1'), isTrue);
      expect(isSpfContent('v=spf1 -all'), isTrue);
      expect(isSpfContent('v=spf1 include:spf.partner.example ~all'), isTrue);
    });

    test('a value merely beginning with the characters is not SPF', () {
      // Counted toward the two-record refusal, such a value would refuse a live domain over
      // something receivers never read as SPF.
      expect(isSpfContent('v=spf1x something'), isFalse);
      expect(isSpfContent('verification=v=spf1'), isFalse);
    });
  });

  group('asking whether an address is listed', () {
    test('finds the address as a whole token', () {
      expect(spfListsIp4('v=spf1 ip4:$address -all', address), isTrue);
    });

    test('never matches inside a longer address', () {
      // The off-by-one that quietly re-authorises the wrong machine: 10.0.0.1 must not be found
      // inside 10.0.0.10.
      expect(spfListsIp4('v=spf1 ip4:10.0.0.10 -all', '10.0.0.1'), isFalse);
      expect(spfListsIp4('v=spf1 ip4:10.0.0.1 -all', '10.0.0.10'), isFalse);
    });
  });

  group('merging into an existing record', () {
    test('inserts before the trailing all-mechanism and keeps its qualifier', () {
      expect(
        spfMerged('v=spf1 include:spf.partner.example ~all', address),
        'v=spf1 include:spf.partner.example ip4:$address ~all',
      );
    });

    test('keeps every existing mechanism byte for byte', () {
      expect(
        spfMerged('v=spf1 a mx include:spf.partner.example ip4:198.51.100.7 -all', address),
        'v=spf1 a mx include:spf.partner.example ip4:198.51.100.7 ip4:$address -all',
      );
    });

    test('appends where the record has no all-mechanism', () {
      expect(
        spfMerged('v=spf1 include:spf.partner.example', address),
        'v=spf1 include:spf.partner.example ip4:$address',
      );
    });

    test('answers null where the address is already authorised, so nothing is rewritten', () {
      expect(spfMerged('v=spf1 ip4:$address -all', address), isNull);
    });
  });

  group('a fresh record', () {
    test('carries the version, the address and the closing mechanism the row chose', () {
      expect(spfFresh('-all', address), 'v=spf1 ip4:$address -all');
      expect(spfFresh('~all', address), 'v=spf1 ip4:$address ~all');
    });
  });

  group('naming what belongs to other senders', () {
    test('reports every mechanism that is not ours and not the closing one', () {
      expect(
        spfForeignMechanisms('v=spf1 include:spf.partner.example ip4:$address a -all', address),
        'include:spf.partner.example a',
      );
    });

    test('reports nothing for a record that is only ours', () {
      expect(spfForeignMechanisms('v=spf1 ip4:$address -all', address), isEmpty);
    });
  });

  group('reading a stored TXT value back', () {
    test('strips the outer quotes and the joins of a chunked value', () {
      expect(
        dechunkedTxt('"v=DKIM1; h=sha256; k=rsa; " "p=abcDEF123"'),
        'v=DKIM1; h=sha256; k=rsa; p=abcDEF123',
      );
    });

    test('leaves an unquoted value untouched', () {
      expect(dechunkedTxt('v=spf1 -all'), 'v=spf1 -all');
    });
  });
}
