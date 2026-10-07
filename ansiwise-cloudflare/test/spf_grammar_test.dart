import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';
import 'package:test/test.dart';

/// The pure SPF surgery the merge step rests on.
///
/// Every case here is the anatomy of one expensive mistake. A merge that loses another service's
/// `include:` takes that service's mail down; one that loses the qualifier of the all-mechanism
/// rewrites the domain's policy; one that matches a mechanism inside a longer one authorises a
/// machine nobody meant. The functions are pure so each of those can be pinned without a network.
void main() {
  group('recognising SPF', () {
    test('the version term is the exact word, alone or followed by mechanisms', () {
      expect(isSpfContent('v=spf1'), isTrue);
      expect(isSpfContent('v=spf1 -all'), isTrue);
      expect(isSpfContent('v=spf1 include:spf.example.net ~all'), isTrue);
    });

    test('a value merely beginning with the characters is not SPF', () {
      // Counted toward the two-record refusal, such a value would refuse a live domain over
      // something receivers never read as SPF.
      expect(isSpfContent('v=spf1x something'), isFalse);
      expect(isSpfContent('verification=v=spf1'), isFalse);
    });
  });

  group('validating host names', () {
    test('accepts lower-case dot-separated host names', () {
      expect(isDnsHostName('mail.example.org'), isTrue);
      expect(isDnsHostName('example.com'), isTrue);
    });

    test('rejects IPv4 addresses, uppercase, and malformed labels', () {
      expect(isDnsHostName('192.0.2.10'), isFalse);
      expect(isDnsHostName('Mail.Example.org'), isFalse);
      expect(isDnsHostName('-x.example.org'), isFalse);
      expect(isDnsHostName('x-.example.org'), isFalse);
    });
  });

  group('the SPF mechanism for a host', () {
    test('uses bare a when host equals apex, and a:host otherwise', () {
      expect(spfMechanism('example.com', 'example.com'), 'a');
      expect(spfMechanism('example.com', 'mail.example.org'), 'a:mail.example.org');
    });
  });

  group('asking whether a mechanism is listed', () {
    test('finds the mechanism as a whole token', () {
      expect(spfListsMechanism('v=spf1 a:mail.example.org -all', 'a:mail.example.org'), isTrue);
      expect(spfListsMechanism('v=spf1 a -all', 'a'), isTrue);
    });

    test('never matches inside a longer mechanism', () {
      expect(spfListsMechanism('v=spf1 a:mail.example.org -all', 'a'), isFalse);
      expect(spfListsMechanism('v=spf1 a:mail.example.org -all', 'a:mail'), isFalse);
      expect(spfListsMechanism('v=spf1 a:mail -all', 'a:mail.example.org'), isFalse);
    });
  });

  group('merging into an existing record', () {
    const String host = 'mail.example.org';
    const String mechanism = 'a:$host';

    test('inserts before the trailing all-mechanism and keeps its qualifier', () {
      expect(
        spfMerged('v=spf1 include:spf.example.net ~all', mechanism),
        'v=spf1 include:spf.example.net a:$host ~all',
      );
    });

    test('keeps every existing mechanism byte for byte', () {
      expect(
        spfMerged('v=spf1 a mx include:spf.example.net ip4:198.51.100.7 -all', mechanism),
        'v=spf1 a mx include:spf.example.net ip4:198.51.100.7 a:$host -all',
      );
    });

    test('appends where the record has no all-mechanism', () {
      expect(
        spfMerged('v=spf1 include:spf.example.net', mechanism),
        'v=spf1 include:spf.example.net a:$host',
      );
    });

    test('answers null where the mechanism is already authorised, so nothing is rewritten', () {
      expect(spfMerged('v=spf1 a:$host -all', mechanism), isNull);
      expect(spfMerged('v=spf1 a -all', 'a'), isNull);
    });

    test('replaces an address token when replacesAddress is given', () {
      expect(
        spfMerged(
          'v=spf1 include:spf.example.net ip4:192.0.2.10 ~all',
          mechanism,
          replacesAddress: '192.0.2.10',
        ),
        'v=spf1 include:spf.example.net a:$host ~all',
      );
    });

    test('preserves other ip4 mechanisms when replacing one', () {
      expect(
        spfMerged(
          'v=spf1 ip4:198.51.100.7 ip4:192.0.2.10 ~all',
          mechanism,
          replacesAddress: '192.0.2.10',
        ),
        'v=spf1 ip4:198.51.100.7 a:$host ~all',
      );
    });

    test('never replaces inside a longer address token', () {
      expect(
        spfMerged('v=spf1 ip4:192.0.2.100 ~all', mechanism, replacesAddress: '192.0.2.10'),
        'v=spf1 ip4:192.0.2.100 a:$host ~all',
      );
      expect(
        spfMerged('v=spf1 ip4:192.0.2.1 ~all', mechanism, replacesAddress: '192.0.2.10'),
        'v=spf1 ip4:192.0.2.1 a:$host ~all',
      );
    });

    test('drops the replaced address when the mechanism is already present', () {
      expect(
        spfMerged('v=spf1 a:$host ip4:192.0.2.10 ~all', mechanism, replacesAddress: '192.0.2.10'),
        'v=spf1 a:$host ~all',
      );
    });
  });

  group('a fresh record', () {
    test('carries the version, the mechanism and the closing mechanism the row chose', () {
      expect(spfFresh('-all', 'a:mail.example.org'), 'v=spf1 a:mail.example.org -all');
      expect(spfFresh('~all', 'a'), 'v=spf1 a ~all');
    });
  });

  group('naming what belongs to other senders', () {
    const String host = 'mail.example.org';
    const String mechanism = 'a:$host';

    test('reports every mechanism that is not ours and not the closing one', () {
      expect(
        spfForeignMechanisms('v=spf1 include:spf.example.net a:$host a -all', mechanism),
        'include:spf.example.net a',
      );
    });

    test('reports nothing for a record that is only ours', () {
      expect(spfForeignMechanisms('v=spf1 a:$host -all', mechanism), isEmpty);
      expect(spfForeignMechanisms('v=spf1 a -all', 'a'), isEmpty);
    });

    test('ignores the address being replaced', () {
      expect(
        spfForeignMechanisms(
          'v=spf1 include:spf.example.net ip4:192.0.2.10 -all',
          mechanism,
          replacesAddress: '192.0.2.10',
        ),
        'include:spf.example.net',
      );
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
