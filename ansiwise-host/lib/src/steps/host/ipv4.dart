/// IPv4 range arithmetic for the steps that read addresses off a machine.
///
/// The arithmetic is done in Dart's 64-bit integers and masked back to 32 bits explicitly at the
/// end. A 32-bit implementation overflows on a `/0`, where the mask is meant to be zero so that
/// everything overlaps, and produces the opposite answer.
library;

/// Whether [value] is a range this arithmetic can read — an address, a slash and a prefix.
bool isCidr(String value) => _Range.parse(value) != null;

/// Whether [address] — a dotted quad with no prefix — lies inside [cidr].
bool cidrContains(String cidr, String address) {
  final _Range? range = _Range.parse(cidr);
  final _Range? point = _Range.parse('$address/32');
  if (range == null || point == null) {
    return false;
  }
  final int mask = range.prefix == 0 ? 0 : (((1 << 32) - (1 << (32 - range.prefix))) & 0xFFFFFFFF);
  return (range.address & mask) == (point.address & mask);
}

/// One IPv4 range, as an address and a prefix length.
final class _Range {
  const _Range(this.address, this.prefix);

  /// The range [value] describes, or null when it is not one.
  static _Range? parse(String value) {
    final List<String> halves = value.split('/');
    if (halves.length != 2) {
      return null;
    }
    final int? prefix = int.tryParse(halves[1]);
    if (prefix == null || prefix < 0 || prefix > 32) {
      return null;
    }
    final int? address = _address(halves[0]);
    return address == null ? null : _Range(address, prefix);
  }

  /// The dotted quad [value] as a number, or null when it is not one.
  static int? _address(String value) {
    final List<String> octets = value.split('.');
    if (octets.length != 4) {
      return null;
    }
    int address = 0;
    for (final String octet in octets) {
      final int? part = int.tryParse(octet);
      if (part == null || part < 0 || part > 255 || (octet.length > 1 && octet.startsWith('0'))) {
        return null;
      }
      address = (address << 8) | part;
    }
    return address;
  }

  final int address;
  final int prefix;
}
