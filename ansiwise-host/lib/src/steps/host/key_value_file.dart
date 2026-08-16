/// A file of `KEY=value` lines, read together with the template it is made from.
///
/// A tree meant to serve many installations carries such a file with every value empty, and a run
/// turns that copy into one installation's own by filling the keys it was given and copying every
/// other line through untouched. Which file, which keys and which values are the caller's; what is
/// here is what may be written and what may not.
///
/// **Filling in place and not appending.** Each key is rewritten at the position the template
/// declares it, so it appears exactly once and keeps the paragraph of explanation above it — which
/// is the only documentation an operator opening the file ever gets. Appending produced a file that
/// carried the same variable twice, the second one blank, and the value that lost was the one
/// somebody typed.
///
/// **Three rules the shell implementation paid for, carried over here.**
///
/// 1. **A value is data, never syntax.** The shell wrote these with `sed`, whose replacement text
///    eats a backslash and an ampersand, so a pasted credential could rewrite the line it was
///    written into. Nothing here interpolates a value into anything: the file is produced as text
///    and handed to `Files.write`, which is also what verifies it by reading it back — `sed` exited
///    zero whether or not it had matched, and a key the template does not declare was reported as
///    filled while the file kept nothing at all. [KeyValueFile.missingKeys] answers that question
///    BEFORE anything is written.
/// 2. **A value still equal to the template's is not an answer.** `LETSENCRYPT_EMAIL` reads
///    `user@example.com` in the template, which is a mailbox nobody reads, and a blanket "does it
///    look like an example" test threw away a `UNIT_APEX` of `example.com` that was a legitimate
///    answer for the installation whose zone that is. So the comparison is per key and against the
///    template itself. See [KeyValueFile.isUnset].
/// 3. **A value that is set is left exactly as it is.** These files gain values after the install —
///    the root token and unseal keys of a running Vault, the generated registry passwords, a
///    rotation somebody performed by hand. A re-run that rewrote them would take the keys to a live
///    Vault away, so a key that carries anything other than the template's own value is never
///    touched again — the same [KeyValueFile.isUnset] decides this and the point above, so the two
///    cannot come apart.
library;

/// One `KEY=value` file, beside the template it was made from.
///
/// Immutable: [filled] produces new text rather than editing this one, so the check that decides
/// what to write and the apply that writes it are reading the same thing.
final class KeyValueFile {
  /// Reads [current] against the [template] it was copied from.
  ///
  /// [current] is the template itself for a file that is not on the machine yet, which is what makes
  /// creating and re-filling the same operation.
  const KeyValueFile({required this.template, required this.current});

  /// What the trunk ships: every key at its placeholder.
  final String template;

  /// What the machine holds now.
  final String current;

  /// The value [current] holds for [key], or null when it declares no such key.
  String? valueOf(String key) => _valueIn(current, key);

  /// Whether [key] has never been answered.
  ///
  /// Empty, absent, or still exactly what the template carries. The last of the three is the one
  /// that is not obvious and the one that was got wrong: a key copied straight out of the template
  /// LOOKS filled, and taking it for an answer puts certificate mail and the identity provider's
  /// first account on a mailbox nobody reads.
  bool isUnset(String key) {
    final String? held = _valueIn(current, key);
    if (held == null || held.isEmpty) {
      return true;
    }
    return held == _valueIn(template, key);
  }

  /// Which of [keys] the TEMPLATE does not declare, in the order given.
  ///
  /// A key nothing declares cannot be filled in place, and writing it anyway would put a bare
  /// assignment at the end of a file whose whole value is that each key stands under the paragraph
  /// explaining it. It is a defect in the template rather than in the answer, so it is reported by
  /// name and nothing is written.
  List<String> missingKeys(Iterable<String> keys) => <String>[
    for (final String key in keys)
      if (_valueIn(template, key) == null) key,
  ];

  /// [current] with each entry of [values] written at the position the template declares it.
  ///
  /// The value is double-quoted, because these files are read by a shell, and the caller has already
  /// been refused if it holds a double quote — see [holdsQuote]. Every other line is copied through
  /// byte for byte.
  String filled(Map<String, String> values) =>
      <String>[for (final String line in current.split('\n')) _rewritten(line, values)].join('\n');

  /// Whether [value] carries a character these files cannot hold.
  ///
  /// A double quote would end the quoting one line early and turn the rest of the file into
  /// something a shell reads as syntax; a newline would split one assignment into two. Neither can
  /// be escaped into safety here, because the file is read by more than one program — so the value
  /// is refused rather than mangled.
  static bool holdsQuote(String value) => value.contains('"') || value.contains('\n');

  /// [line] rewritten when it assigns one of [values], and [line] itself otherwise.
  static String _rewritten(String line, Map<String, String> values) {
    final String? key = _assignedKey(line);
    if (key == null) {
      return line;
    }
    final String? value = values[key];
    return value == null ? line : '$key="$value"';
  }

  /// The value assigned to [key] somewhere in [text], or null when nothing assigns it.
  ///
  /// The surrounding quotes are taken off, and a trailing comment with them, because that is how the
  /// value reads to the shell that sources the file. A commented-out assignment is not one: the
  /// template carries three of those as suggestions an operator may switch on, and reading one as
  /// the current value would report a chart version as pinned that nothing pins.
  static String? _valueIn(String text, String key) {
    for (final String raw in text.split('\n')) {
      final String line = raw.trim();
      if (line.startsWith('#') || !line.startsWith('$key=')) {
        continue;
      }
      return _unquoted(line.substring(key.length + 1).trim());
    }
    return null;
  }

  /// The key [line] assigns, or null when it assigns nothing.
  static String? _assignedKey(String line) {
    final int equals = line.indexOf('=');
    if (equals <= 0 || line.trimLeft() != line) {
      return null;
    }
    final String key = line.substring(0, equals);
    return _keyPattern.hasMatch(key) ? key : null;
  }

  static String _unquoted(String value) {
    final int comment = _commentOutsideQuotes(value);
    final String written = (comment < 0 ? value : value.substring(0, comment)).trim();
    if (written.length >= 2) {
      final String first = written[0];
      if ((first == '"' || first == "'") && written.endsWith(first)) {
        return written.substring(1, written.length - 1);
      }
    }
    return written;
  }

  /// Where a trailing comment starts in [value], or -1 when there is none.
  ///
  /// A `#` inside quotes is part of the value — a bcrypt hash and a URL fragment both carry one —
  /// so the quoting has to be followed rather than the first `#` taken.
  static int _commentOutsideQuotes(String value) {
    String? quote;
    for (int i = 0; i < value.length; i++) {
      final String character = value[i];
      if (quote == null && (character == '"' || character == "'")) {
        quote = character;
        continue;
      }
      if (quote == character) {
        quote = null;
        continue;
      }
      if (quote == null && character == '#') {
        return i;
      }
    }
    return -1;
  }
}

/// A shell variable name, which is what stands to the left of an assignment these files carry.
final RegExp _keyPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
