/// The RSA key formats, for the step that mints the mail signing key pair into the store.
///
/// **A FORMAT, not a second tool.** Nothing here computes a key, reads a configuration file or
/// knows that a mail server exists. What it knows is how an RSA key pair is written down, which is
/// fixed outside this organisation and the same for everybody: the PKCS#8 container an unencrypted
/// private key stands in (`BEGIN PRIVATE KEY`, what `openssl genpkey` writes), the older PKCS#1 one
/// (`BEGIN RSA PRIVATE KEY`) a key made by hand may stand in, and the SubjectPublicKeyInfo a DKIM
/// record's `p=` carries as one line of base64 — RFC 6376 names exactly that encoding.
///
/// **The public half is COPIED out of the private one, never computed.** The modulus and the public
/// exponent stand in a private key's DER as its second and third integer, and a public key is those
/// two integers in the container receivers expect. So a public half read here can never disagree
/// with the private one it was read out of, which is the property the signer and the record depend
/// on; arithmetic written here could get that wrong in a way nothing would notice until receivers
/// failed every signature.
///
/// **What a private key looks like**, because reading it is what this file is for:
///
/// ```text
/// PrivateKeyInfo ::= SEQUENCE {            PKCS#8, the outer container
///   version         INTEGER (0),
///   algorithm       SEQUENCE { OID rsaEncryption, NULL },
///   privateKey      OCTET STRING  -- holding the RSAPrivateKey below
/// }
/// RSAPrivateKey ::= SEQUENCE {             PKCS#1, the key itself
///   version         INTEGER (0),
///   modulus         INTEGER,      -- n
///   publicExponent  INTEGER,      -- e
///   ...                           -- the private numbers, never read here
/// }
/// SubjectPublicKeyInfo ::= SEQUENCE {      what the record carries
///   algorithm       SEQUENCE { OID rsaEncryption, NULL },
///   subjectPublicKey BIT STRING  -- holding SEQUENCE { modulus, publicExponent }
/// }
/// ```
///
/// Every DER value is a tag, a length and that many bytes of content; a length of 128 or more is
/// written as a count of length bytes followed by the length itself.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The first line of an unencrypted private key in the PKCS#8 container.
const String rsaPrivateKeyOpening = '-----BEGIN PRIVATE KEY-----';

/// The last line of that container.
const String rsaPrivateKeyClosing = '-----END PRIVATE KEY-----';

/// The first line of a private key in the PKCS#1 container.
const String pkcs1PrivateKeyOpening = '-----BEGIN RSA PRIVATE KEY-----';

/// The last line of that container.
const String pkcs1PrivateKeyClosing = '-----END RSA PRIVATE KEY-----';

/// The DER of the rsaEncryption algorithm identifier, 1.2.840.113549.1.1.1 with its NULL parameter,
/// as it stands in every container above.
const List<int> _rsaAlgorithm = <int>[
  0x30, 0x0d, //
  0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, //
  0x05, 0x00,
];

const int _sequenceTag = 0x30;
const int _integerTag = 0x02;
const int _bitStringTag = 0x03;
const int _octetStringTag = 0x04;

/// The `p=` value of a DKIM record for the private key in [pem]: the SubjectPublicKeyInfo of its
/// public half, as the one line of base64 the record carries.
///
/// Null where [pem] is not an unencrypted RSA private key this can read — not one of the two
/// containers above, or bytes inside them that do not parse as one. A value that cannot be read is
/// a value the caller must not write over, so "unreadable" is an answer of its own here and never
/// a guess.
String? dkimPublicKeyIn(String pem) {
  final _Container? container = _Container.of(pem);
  if (container == null) {
    return null;
  }
  final _Node? outer = _Node.at(container.der, 0);
  if (outer == null || outer.tag != _sequenceTag || outer.end != container.der.length) {
    return null;
  }
  final Uint8List? rsaPrivateKey = container.pkcs8 ? _privateKeyOf(outer) : container.der;
  if (rsaPrivateKey == null) {
    return null;
  }
  final _Node? key = _Node.at(rsaPrivateKey, 0);
  if (key == null || key.tag != _sequenceTag) {
    return null;
  }
  final List<_Node>? fields = key.children();
  if (fields == null || fields.length < 3) {
    return null;
  }
  final _Node version = fields[0];
  final _Node modulus = fields[1];
  final _Node exponent = fields[2];
  if (version.tag != _integerTag || modulus.tag != _integerTag || exponent.tag != _integerTag) {
    return null;
  }
  // Version 0 is a two-prime key, the only kind the container above describes; anything else is a
  // key whose layout this file does not know and must not pretend to.
  if (version.content.length != 1 || version.content[0] != 0) {
    return null;
  }
  final Uint8List publicKey = _sequence(<List<int>>[modulus.encoded, exponent.encoded]);
  final Uint8List info = _sequence(<List<int>>[_rsaAlgorithm, _bitString(publicKey)]);
  return base64.encode(info);
}

/// The RSAPrivateKey inside a PKCS#8 [info], or null where the container names another algorithm
/// or does not have the shape the header of this file states.
Uint8List? _privateKeyOf(_Node info) {
  final List<_Node>? fields = info.children();
  if (fields == null || fields.length < 3) {
    return null;
  }
  final _Node version = fields[0];
  final _Node algorithm = fields[1];
  final _Node privateKey = fields[2];
  if (version.tag != _integerTag || version.content.length != 1 || version.content[0] != 0) {
    return null;
  }
  if (!_same(algorithm.encoded, _rsaAlgorithm)) {
    return null;
  }
  if (privateKey.tag != _octetStringTag) {
    return null;
  }
  return privateKey.content;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

/// One DER value: its tag, its content, and the bytes of the whole thing.
final class _Node {
  const _Node({required this.tag, required this.content, required this.encoded, required this.end});

  /// The value that starts at [offset] of [bytes], or null where the bytes there are not one.
  static _Node? at(Uint8List bytes, int offset) {
    if (offset + 2 > bytes.length) {
      return null;
    }
    final int tag = bytes[offset];
    int length = bytes[offset + 1];
    int headerLength = 2;
    if (length >= 0x80) {
      final int lengthBytes = length & 0x7f;
      if (lengthBytes == 0 || lengthBytes > 4 || offset + 2 + lengthBytes > bytes.length) {
        return null;
      }
      length = 0;
      for (int i = 0; i < lengthBytes; i++) {
        length = (length << 8) | bytes[offset + 2 + i];
      }
      headerLength = 2 + lengthBytes;
    }
    final int end = offset + headerLength + length;
    if (end > bytes.length) {
      return null;
    }
    return _Node(
      tag: tag,
      content: Uint8List.sublistView(bytes, offset + headerLength, end),
      encoded: Uint8List.sublistView(bytes, offset, end),
      end: end,
    );
  }

  final int tag;
  final Uint8List content;
  final Uint8List encoded;

  /// Where the next value after this one starts, in the bytes this was read out of.
  final int end;

  /// The values this one is made of, in order, or null where the content does not divide into
  /// values exactly.
  List<_Node>? children() {
    final List<_Node> found = <_Node>[];
    int offset = 0;
    while (offset < content.length) {
      final _Node? next = _Node.at(content, offset);
      if (next == null) {
        return null;
      }
      found.add(next);
      offset = next.end;
    }
    return found;
  }
}

/// A DER length, in the short form below 128 and the long form from there.
List<int> _length(int length) {
  if (length < 0x80) {
    return <int>[length];
  }
  final List<int> bytes = <int>[];
  int rest = length;
  while (rest > 0) {
    bytes.insert(0, rest & 0xff);
    rest >>= 8;
  }
  return <int>[0x80 | bytes.length, ...bytes];
}

Uint8List _sequence(List<List<int>> parts) {
  final List<int> content = <int>[for (final List<int> part in parts) ...part];
  return Uint8List.fromList(<int>[_sequenceTag, ..._length(content.length), ...content]);
}

/// A BIT STRING holding whole bytes: the count of unused bits, zero, then the bytes.
List<int> _bitString(List<int> bytes) => <int>[
  _bitStringTag,
  ..._length(bytes.length + 1),
  0x00,
  ...bytes,
];

/// The DER between the marker lines of one of the two containers, and which one it was.
final class _Container {
  const _Container({required this.der, required this.pkcs8});

  static _Container? of(String pem) {
    final List<String> lines = const LineSplitter()
        .convert(pem)
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList();
    if (lines.length < 3) {
      return null;
    }
    final bool pkcs8;
    if (lines.first == rsaPrivateKeyOpening && lines.last == rsaPrivateKeyClosing) {
      pkcs8 = true;
    } else if (lines.first == pkcs1PrivateKeyOpening && lines.last == pkcs1PrivateKeyClosing) {
      pkcs8 = false;
    } else {
      return null;
    }
    final Uint8List der;
    try {
      der = base64.decode(lines.sublist(1, lines.length - 1).join());
    } on FormatException {
      return null;
    }
    return _Container(der: der, pkcs8: pkcs8);
  }

  final Uint8List der;
  final bool pkcs8;
}
