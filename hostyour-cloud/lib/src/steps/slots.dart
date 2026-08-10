/// The one notation for a value that cannot be written down where it is needed: a marked slot.
///
/// A slot is a NAME in angle brackets — `<stage>`, `<version>`, `<master-domain>` — standing where
/// exactly one value belongs. No expression, no condition and no loop, so what a reader has in
/// front of them is the text that will be used, never a language for producing it. Every filling
/// in this plugin goes through here — a program row's argument, a pinned release url, a template
/// beside the programs — which is what makes it ONE notation with one grammar, instead of each
/// step teaching the reader its own.
///
/// **What still looks like a slot after filling is for the caller to refuse, and [leftoverSlotIn]
/// is deliberately broader than [slotPattern].** A misspelled or mis-cased name — `<Stage>`,
/// `<verison>` — matches no declared slot, so a scan that only knew the grammar would wave it
/// through to the tool the text is bound for, where it is taken as content. The scan therefore
/// reports ANYTHING between angle brackets. The one text that must not be scanned this way is
/// another tool's arbitrary content, where angle brackets can be legitimate — such a caller fills
/// its declared slot and judges nothing else.
library;

/// A slot: a lower-case name in angle brackets, and nothing that could be an expression.
final RegExp slotPattern = RegExp('<([a-z][a-z0-9-]*)>');

/// The slot names [text] carries, each named once, in the order they first appear.
List<String> slotsIn(String text) {
  final List<String> found = <String>[];
  for (final RegExpMatch match in slotPattern.allMatches(text)) {
    if (match.group(1) case final String name when !found.contains(name)) {
      found.add(name);
    }
  }
  return found;
}

/// [text] with the slot named by each entry of [values] holding that entry's value.
///
/// A name with no slot in [text] is left for the caller to judge: an argument is free to use any
/// part of what a run holds, while a template refuses a value with nowhere to go — that law
/// belongs to the caller, not to the notation.
String filledSlots(String text, Map<String, String> values) {
  String written = text;
  for (final MapEntry<String, String> value in values.entries) {
    written = written.replaceAll('<${value.key}>', value.value);
  }
  return written;
}

/// The first thing in [text] that still looks like a slot, or null when nothing does.
String? leftoverSlotIn(String text) => _anySlot.firstMatch(text)?.group(0);

/// Any `<...>` at all, for the refusal that catches a name nothing filled — including one the
/// grammar would not accept, which is exactly what a misspelling looks like.
final RegExp _anySlot = RegExp('<[^<>]*>');
