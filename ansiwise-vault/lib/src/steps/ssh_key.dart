/// The OpenSSH key formats, for the step that mints a key pair into the store.
///
/// **A FORMAT, not a second tool.** Nothing here starts `ssh-keygen`, reads a configuration file or
/// knows that a daemon exists. What it knows is how an ed25519 key pair is written down, which is
/// fixed outside this organisation and the same for everybody: the `openssh-key-v1` container a
/// private key stands in, the one-line form a public key is handed out in, and the digest a
/// fingerprint is. A vendor with a secret store and no machine of ours reads exactly the same bytes.
///
/// **The curve arithmetic is not written here and must not be.** Turning a seed into a public key is
/// the one part where a subtle error yields a key pair whose halves do not match — nothing on this
/// side would notice, and what shows up months later is a login refused. It is asked of a library
/// that does nothing else.
///
/// **What the container looks like**, because reading it back is half of what this file is for:
///
/// ```text
/// "openssh-key-v1\0"
/// string  cipher      "none"
/// string  kdf         "none"
/// string  kdf options ""
/// uint32  keys        1
/// string  public key  string "ssh-ed25519" + string pub(32)
/// string  private     uint32 check + uint32 check + string "ssh-ed25519"
///                     + string pub(32) + string priv(64) + string comment + padding
/// ```
///
/// A `string` is a big-endian uint32 length followed by that many bytes. The whole container is
/// base64 and stands between two marker lines.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';

/// The name ed25519 carries inside every OpenSSH key blob and on every public key line.
const String sshEd25519 = 'ssh-ed25519';

/// How many bytes an ed25519 seed and an ed25519 public key each hold.
const int ed25519KeyBytes = 32;

/// How many bytes the container's private field holds: the seed and the public key behind it.
const int ed25519PrivateBytes = 64;

/// How many bytes the two equal check numbers of the container hold together.
const int sshCheckBytes = 4;

/// One ed25519 key pair, in the two forms whatever reads it expects.
final class SshKeyPair {
  /// Holds the pair as it is written down.
  const SshKeyPair({required this.privateKey, required this.publicKey});

  /// The private half, as the whole `openssh-key-v1` container including its line breaks.
  final String privateKey;

  /// The public half, as the one line an `authorized_keys` file carries.
  final String publicKey;
}

/// An ed25519 key pair grown from [seed], carrying [comment].
///
/// [seed] is 64 hexadecimal characters — the 32 bytes the private half IS — and [check] is 8, the
/// number the container repeats twice. With no cipher on the container that number proves nothing
/// about the key; it is what a reader compares the two copies of to tell a wrong passphrase from a
/// broken file, and it is written unpredictable because that is the shape every other writer of this
/// format produces.
///
/// Throws [FormatException] where either text is not hexadecimal of the length said above.
Future<SshKeyPair> mintedSshKeyPair({
  required String seed,
  required String check,
  required String comment,
}) async {
  final Uint8List seedBytes = _bytesOfHex(seed, 'seed', ed25519KeyBytes);
  final Uint8List checkBytes = _bytesOfHex(check, 'check', sshCheckBytes);

  final SimpleKeyPair pair = await Ed25519().newKeyPairFromSeed(seedBytes);
  final SimplePublicKey public = await pair.extractPublicKey();
  final Uint8List publicBytes = Uint8List.fromList(public.bytes);

  final Uint8List blob = _publicKeyBlob(publicBytes);
  final BytesBuilder secret = BytesBuilder()
    ..add(checkBytes)
    ..add(checkBytes)
    ..add(_string(ascii.encode(sshEd25519)))
    ..add(_string(publicBytes))
    ..add(_string(Uint8List.fromList(<int>[...seedBytes, ...publicBytes])))
    ..add(_string(utf8.encode(comment)));
  // The padding is 1, 2, 3 … up to the cipher's block size, which is eight for an unencrypted
  // container. A reader checks the counting, so it is not free bytes.
  for (int i = 1; secret.length % _paddingBlock != 0; i++) {
    secret.addByte(i);
  }

  final BytesBuilder container = BytesBuilder()
    ..add(_head)
    ..add(_string(ascii.encode(_none)))
    ..add(_string(ascii.encode(_none)))
    ..add(_string(Uint8List(0)))
    ..add(_uint32(1))
    ..add(_string(blob))
    ..add(_string(secret.toBytes()));

  return SshKeyPair(
    privateKey: _armoured(container.toBytes()),
    publicKey: _publicKeyLine(blob, comment),
  );
}

/// The public half [privateKey] carries, as the one line it is handed out on, or null where the text
/// is not a usable unencrypted ed25519 container.
///
/// **This is what makes a second run leave a key alone.** A key pair already in the store must not be
/// minted again, and the row after it still has to be given the public half — so it is read back out
/// of the private one rather than re-derived by anything that could disagree. The comment is read
/// from the container too, so the line this returns is the one the mint wrote, character for
/// character, and nothing appends a second copy of the same key to a file.
///
/// **Null means "do not touch this".** A container that will not parse, one that is encrypted, one
/// whose two halves do not belong together — each is a value some other writer owns or a file that
/// came back damaged, and writing over it would take away the access whatever holds the matching
/// public half still has.
String? sshPublicKeyIn(String privateKey) {
  final Uint8List? container = _unarmoured(privateKey);
  if (container == null) {
    return null;
  }
  final _Reader reader = _Reader(container);
  final Uint8List? magic = reader.take(_head.length);
  if (magic == null || !_sameBytes(magic, _head)) {
    return null;
  }
  // A cipher or a key derivation means a passphrase, and nothing here holds one. Answered as
  // unreadable rather than as absent, because the two lead a step to opposite acts.
  final String? cipher = reader.text();
  final String? derivation = reader.text();
  final Uint8List? derivationOptions = reader.string();
  if (cipher != _none || derivation != _none || derivationOptions == null) {
    return null;
  }
  if (reader.uint32() != 1) {
    return null;
  }
  final Uint8List? blob = reader.string();
  final Uint8List? secret = reader.string();
  if (blob == null || secret == null) {
    return null;
  }

  final _Reader inside = _Reader(blob);
  if (inside.text() != sshEd25519) {
    return null;
  }
  final Uint8List? public = inside.string();
  if (public == null || public.length != ed25519KeyBytes) {
    return null;
  }

  final _Reader held = _Reader(secret);
  final Uint8List? first = held.take(sshCheckBytes);
  final Uint8List? second = held.take(sshCheckBytes);
  if (first == null || second == null || !_sameBytes(first, second)) {
    return null;
  }
  if (held.text() != sshEd25519) {
    return null;
  }
  final Uint8List? publicAgain = held.string();
  final Uint8List? private = held.string();
  final String? comment = held.text();
  if (publicAgain == null || private == null || comment == null) {
    return null;
  }
  // THE TWO HALVES HAVE TO BELONG TOGETHER. The container writes the public key twice and the
  // private field ends with it a third time; a value where those disagree is not a key pair, and a
  // step that took the first of them would publish a public half nothing can log in with.
  if (!_sameBytes(public, publicAgain) || private.length != ed25519PrivateBytes) {
    return null;
  }
  if (!_sameBytes(public, Uint8List.sublistView(private, ed25519KeyBytes))) {
    return null;
  }
  return _publicKeyLine(_publicKeyBlob(public), comment);
}

/// The fingerprint of the public key on [line], in the form `SHA256:` and the digest without its
/// padding, or null where the line is not a public key.
///
/// That form is not a choice made here. It is what every reader of a fingerprint compares against —
/// the second field of what `ssh-keygen -l` prints, and what a client computes for the key a host
/// presents — so a digest written any other way is one nothing recognises.
///
/// **The blob is read, not only decoded.** A line whose base64 decodes to something that does not
/// begin with the algorithm the line names is a damaged or truncated file, and it would otherwise
/// yield a fingerprint that looks perfectly plausible and matches no host.
String? sshFingerprintOf(String line) {
  final List<String> fields = line.trim().split(RegExp(r'\s+'));
  if (fields.length < 2 || fields[0].isEmpty) {
    return null;
  }
  final Uint8List? blob = _decoded(fields[1]);
  if (blob == null) {
    return null;
  }
  if (_Reader(blob).text() != fields[0]) {
    return null;
  }
  return 'SHA256:${base64.encode(sha256.convert(blob).bytes).replaceAll('=', '')}';
}

/// The first line of an `openssh-key-v1` container, before its base64.
const String sshPrivateKeyOpening = '-----BEGIN OPENSSH PRIVATE KEY-----';

/// The last line of one.
const String sshPrivateKeyClosing = '-----END OPENSSH PRIVATE KEY-----';

/// What stands at the head of every container, before its first field: the name and a zero byte.
final Uint8List _head = Uint8List.fromList(<int>[...ascii.encode('openssh-key-v1'), 0]);

/// What the cipher and the key derivation of an unencrypted container are called.
const String _none = 'none';

/// How many bytes the private section of an unencrypted container is padded to a multiple of.
const int _paddingBlock = 8;

/// How many base64 characters stand on one line of a container.
const int _armourWidth = 70;

/// The public key blob: the algorithm and the key, as one string of bytes.
Uint8List _publicKeyBlob(Uint8List public) =>
    Uint8List.fromList(<int>[..._string(ascii.encode(sshEd25519)), ..._string(public)]);

/// The one line a public key is handed out on, which is the algorithm, the blob and the comment.
String _publicKeyLine(Uint8List blob, String comment) {
  final String written = '$sshEd25519 ${base64.encode(blob)}';
  return comment.isEmpty ? written : '$written $comment';
}

/// [container] between the two marker lines, wrapped the way every writer of this format wraps it.
String _armoured(Uint8List container) {
  final String body = base64.encode(container);
  final StringBuffer written = StringBuffer()..writeln(sshPrivateKeyOpening);
  for (int at = 0; at < body.length; at += _armourWidth) {
    written.writeln(body.substring(at, (at + _armourWidth).clamp(0, body.length)));
  }
  return (written..writeln(sshPrivateKeyClosing)).toString();
}

/// The bytes between the two marker lines of [text], or null where they are not both there or what
/// stands between them is not base64.
Uint8List? _unarmoured(String text) {
  final List<String> lines = const LineSplitter()
      .convert(text)
      .map((String line) => line.trim())
      .toList();
  final int opens = lines.indexOf(sshPrivateKeyOpening);
  final int closes = lines.indexOf(sshPrivateKeyClosing);
  if (opens < 0 || closes <= opens) {
    return null;
  }
  return _decoded(lines.sublist(opens + 1, closes).join());
}

/// [text] decoded as base64, or null where it is not base64 at all.
Uint8List? _decoded(String text) {
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}

/// [text] read as [bytes] bytes of hexadecimal, refusing anything else.
Uint8List _bytesOfHex(String text, String named, int bytes) {
  if (text.length != bytes * 2) {
    throw FormatException(
      'the $named is $bytes bytes, so ${bytes * 2} hexadecimal characters',
      text,
    );
  }
  final Uint8List read = Uint8List(bytes);
  for (int i = 0; i < bytes; i++) {
    final int? byte = int.tryParse(text.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) {
      throw FormatException('the $named is hexadecimal', text, i * 2);
    }
    read[i] = byte;
  }
  return read;
}

/// [value] as the four big-endian bytes the format writes a number in.
Uint8List _uint32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value);

/// [bytes] as a `string` of the format: its length, then it.
Uint8List _string(List<int> bytes) => Uint8List.fromList(<int>[..._uint32(bytes.length), ...bytes]);

/// Whether [a] and [b] hold the same bytes.
bool _sameBytes(Uint8List a, Uint8List b) {
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

/// Reading the fields of a blob in the order they were written.
final class _Reader {
  _Reader(this._bytes);

  final Uint8List _bytes;
  int _at = 0;

  /// The next [count] bytes, or null where there are not that many left.
  Uint8List? take(int count) {
    if (count < 0 || _at + count > _bytes.length) {
      return null;
    }
    final Uint8List read = Uint8List.sublistView(_bytes, _at, _at + count);
    _at += count;
    return read;
  }

  /// The next number, or null where four bytes are not left.
  int? uint32() {
    final Uint8List? read = take(4);
    return read == null ? null : ByteData.sublistView(read).getUint32(0);
  }

  /// The next `string`, or null where its length or its bytes are not there.
  Uint8List? string() {
    final int? length = uint32();
    return length == null ? null : take(length);
  }

  /// The next `string` read as text, or null where there is none or it is not text.
  String? text() {
    final Uint8List? read = string();
    if (read == null) {
      return null;
    }
    try {
      return utf8.decode(read);
    } on FormatException {
      return null;
    }
  }
}
