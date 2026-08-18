/// The scalars helm and this package read differently, found in the text of a values file.
///
/// **Why this exists.** A values file has TWO readers. helm parses YAML 1.1, where a bare number
/// with a leading zero is octal and where `yes`, `no`, `on` and `off` are booleans. This package
/// parses YAML 1.2, which has neither. Neither reader is wrong and neither can be made to imitate
/// the other, so a file carrying one of those shapes means two different things at once.
///
/// **What it costs when nobody looks.** The release installs perfectly — every command returns zero,
/// the chart and version are right — and the step that compares what it asked for against what the
/// release holds compares 400 with 256 and finds them different. It upgrades, asks again, gets the
/// same answer, and reports "the step ran and the machine is still not in the state it produces" on
/// every run, forever. Measured on a real machine, where it stopped a program at step 6 of 64.
///
/// **Scanned as TEXT, on purpose.** By the time either reader has parsed the file the ambiguity is
/// gone: each has already picked its meaning, and the two meanings are what has to be compared. Only
/// what was written carries the question.
library;

/// One place in a values file where the two readers disagree.
final class AmbiguousScalar {
  /// The scalar [written] on line [line], which the two readers read as [asHelmReads] and [asHereRead].
  const AmbiguousScalar({
    required this.line,
    required this.written,
    required this.asHelmReads,
    required this.asHereRead,
  });

  /// Which line of the file carries it, counted from one.
  final int line;

  /// The scalar exactly as the file writes it.
  final String written;

  /// What helm makes of it, reading YAML 1.1.
  final String asHelmReads;

  /// What this package makes of it, reading YAML 1.2.
  final String asHereRead;

  /// The one line a refusal says about this scalar.
  String get sentence =>
      'line $line writes $written, which helm reads as $asHelmReads and this reads as $asHereRead';
}

/// Every scalar in [text] that the two readers disagree about.
///
/// A scalar is looked for only where a VALUE stands — after a `key:` or a `- ` — because that is the
/// only place either reader converts one. A key is text to both, and so is everything inside quotes
/// and everything after a `#` that opens a comment.
List<AmbiguousScalar> ambiguousScalarsIn(String text) {
  final List<AmbiguousScalar> found = <AmbiguousScalar>[];
  final List<String> lines = text.split('\n');
  for (int index = 0; index < lines.length; index++) {
    final String? value = _valueOn(lines[index]);
    if (value == null) {
      continue;
    }
    final AmbiguousScalar? disagreement = _disagreementIn(value, index + 1);
    if (disagreement != null) {
      found.add(disagreement);
    }
  }
  return found;
}

/// What stands where a value stands on [line], or null where the line carries none.
///
/// Everything from an unquoted `#` on is a comment and goes; a line that assigns nothing and lists
/// nothing carries no value at all.
String? _valueOn(String line) {
  final String bare = _withoutComment(line);
  final String trimmed = bare.trimRight();
  if (trimmed.isEmpty) {
    return null;
  }

  // A list entry: the value is what follows the dash. `- key: value` is a mapping inside a list, so
  // the assignment below takes it instead.
  final String afterDash = trimmed.trimLeft().startsWith('- ')
      ? trimmed.trimLeft().substring(2)
      : trimmed;

  final int colon = _assignmentColonIn(afterDash);
  if (colon >= 0) {
    return afterDash.substring(colon + 1).trim();
  }
  return identical(afterDash, trimmed) ? null : afterDash.trim();
}

/// Where the colon that opens a value stands in [line], or -1 where none does.
///
/// A colon inside quotes belongs to the text, and a colon that is not followed by a space or the end
/// of the line is part of the key — `a:b` is one word to YAML, not an assignment.
int _assignmentColonIn(String line) {
  bool inSingle = false;
  bool inDouble = false;
  for (int at = 0; at < line.length; at++) {
    final String character = line[at];
    if (character == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (character == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (character == ':' && !inSingle && !inDouble) {
      if (at + 1 == line.length || line[at + 1] == ' ') {
        return at;
      }
    }
  }
  return -1;
}

/// [line] up to the `#` that opens a comment, or the whole of it where none does.
String _withoutComment(String line) {
  bool inSingle = false;
  bool inDouble = false;
  for (int at = 0; at < line.length; at++) {
    final String character = line[at];
    if (character == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (character == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    // A `#` opens a comment only where a space stands before it, or where it opens the line.
    if (character == '#' && !inSingle && !inDouble && (at == 0 || line[at - 1] == ' ')) {
      return line.substring(0, at);
    }
  }
  return line;
}

/// A leading zero followed by octal digits, which is a number to helm and a different number here.
final RegExp _octal = RegExp(r'^0[0-7]+$');

/// The words YAML 1.1 makes booleans of and YAML 1.2 leaves as text.
const Set<String> _elevenBooleans = <String>{'yes', 'no', 'on', 'off'};

/// What the two readers make of [value], or null where they agree.
AmbiguousScalar? _disagreementIn(String value, int line) {
  if (value.isEmpty) {
    return null;
  }
  // Quoted is unambiguous: both readers take the text and neither converts it. That is the fix this
  // refusal asks for, so it must not be what it reports.
  final String first = value[0];
  if (first == '"' || first == "'") {
    return null;
  }
  if (_octal.hasMatch(value)) {
    return AmbiguousScalar(
      line: line,
      written: value,
      asHelmReads: '${int.parse(value, radix: 8)} — a leading zero is octal in YAML 1.1',
      asHereRead: '${int.parse(value)} — YAML 1.2 has no bare octal',
    );
  }
  if (_elevenBooleans.contains(value.toLowerCase())) {
    final bool yes = value.toLowerCase() == 'yes' || value.toLowerCase() == 'on';
    return AmbiguousScalar(
      line: line,
      written: value,
      asHelmReads: '$yes — YAML 1.1 makes a boolean of it',
      asHereRead: 'the text "$value" — YAML 1.2 knows only true and false',
    );
  }
  return null;
}
