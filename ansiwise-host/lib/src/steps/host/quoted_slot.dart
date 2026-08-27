/// The slots of a template that stand INSIDE quoting, and the values that would end it there.
///
/// **What breaks, and with a value nobody would call wrong.** A template is filled by substituting
/// text, so a slot standing inside a quoted run of text silently hands the value a job nobody gave
/// it: not carrying the character that closes that quoting. `to: '<recipients>'` filled with a
/// mailbox whose local part carries an apostrophe — `o'brien@example.com`, an ordinary address —
/// writes `to: 'o'brien@example.com'`, where the quoting the template opened ends four characters
/// early and everything after it is read as something nobody wrote.
///
/// **The failure lands nowhere near the value.** Measured 2026-08-27 against
/// `alertRecipients: ['<recipients>']`: with a plain address the file reads back as a mapping
/// holding a one-entry list, and with the apostrophe in it the reader raises a parse error naming
/// the line the flow sequence opened on. The whole file is one document, so what is lost is not the
/// one key — nothing in the file can be read.
///
/// **Read as TEXT, never as the grammar of whichever file it is.** A template is any text file a row
/// points this package at — a rule set, a unit, a manifest, a settings file — and this package may
/// not know which. What every one of those grammars shares is the only thing looked for here: a run
/// of text opened with `'` is closed by the next `'`, and one opened with `"` by the next `"` that
/// no backslash escapes.
///
/// **This REFUSES, and repairs nothing.** Nothing here escapes a value for the quoting it lands in,
/// and nothing here lets a slot say which quoting it stands in — both need a notation, and which
/// side declares it is undecided. What is not in question is that a file which cannot be read back
/// is not a file a step may write in silence.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// One slot of a template whose value would end the quoting the slot stands inside.
final class QuotingBroken {
  /// Records that [slot] stands on line [line] inside quoting opened with [quote], and that this
  /// run fills it with a value carrying that same character.
  const QuotingBroken({required this.line, required this.slot, required this.quote});

  /// Which line of the template carries it, counted from one.
  final int line;

  /// The slot exactly as the template writes it, mark and all.
  final String slot;

  /// The character the template opened the quoting with, and that the value closes it with.
  final String quote;

  /// The one line a refusal says about this slot.
  ///
  /// The VALUE is not in it. A slot may be filled from any answer a run holds, a run holds
  /// credentials, and a refusal is written into the record of the run.
  String get sentence =>
      'line $line writes $slot inside $quote quoting, and this run fills it with a value that '
      'carries $quote';
}

/// Every slot of [text] whose value in [values] carries the character that closes the quoting the
/// slot stands inside.
///
/// A slot standing inside no quoting is passed over: there both quote characters are ordinary text
/// and carry no meaning the template did not put there. A slot [values] holds nothing for is passed
/// over too — its line is the framework's to drop or to refuse by name, and neither is this scan's
/// question.
List<QuotingBroken> quotingBrokenIn(String text, Map<String, String> values) {
  final List<QuotingBroken> found = <QuotingBroken>[];
  final List<String> lines = text.split('\n');
  for (int index = 0; index < lines.length; index++) {
    for (final RegExpMatch match in slotPattern.allMatches(lines[index])) {
      final String? quote = _quotingAt(lines[index], match.start);
      if (quote == null) {
        continue;
      }
      final String? value = values[match.group(1)!];
      if (value == null || !value.contains(quote)) {
        continue;
      }
      found.add(QuotingBroken(line: index + 1, slot: match.group(0)!, quote: quote));
    }
  }
  return found;
}

/// The character that opened the quoting standing at [at] in [line], or null where none is open.
///
/// The walk is over the TEMPLATE and not over the filled text. Every quote character it meets is one
/// the template author wrote, and a quote character the VALUE carries is what this is looking for
/// rather than a thing to count — walking the filled text would let the first broken slot on a line
/// shift the reading of the next one.
String? _quotingAt(String line, int at) {
  String? open;
  for (int index = 0; index < at; index++) {
    final String character = line[index];
    // A backslash takes the next character with it inside DOUBLE quoting only, so `"he said \"hi\"
    // to <name>"` keeps the slot inside the quoting the line opened with. Inside single quoting a
    // backslash is an ordinary character to every grammar this package writes, and a doubled `''`
    // needs nothing here: it closes and reopens, which leaves the state where it was.
    if (open == '"' && character == r'\') {
      index++;
      continue;
    }
    if (character == "'" || character == '"') {
      if (open == null) {
        open = character;
      } else if (open == character) {
        open = null;
      }
    }
  }
  return open;
}

/// Rendering a template with the values that cannot stand where they land refused by name.
extension QuotingKept on TemplateStep {
  /// The template at [TemplateStep.templatePath] with [values] in its slots, refusing any value that
  /// would end the quoting its slot stands inside.
  ///
  /// [TemplateRefused] is the same refusal a template that will not fit its run raises, so the two
  /// answers a run gives before it changes anything are the ones already written for it: the check
  /// is BLOCKED and the plan says nothing would be done. An operator reads the template, the line
  /// and the slot at the row that would have written the file, rather than a parse error from
  /// whatever reads the file next.
  ///
  /// **The template is read here only where a value could close any quoting at all.** A value
  /// carrying neither quote character cannot end one, which is nearly every value of nearly every
  /// run, and reading the template is a round trip to the machine paid again on the check, the plan
  /// and the apply of every step that writes one.
  Future<String> renderedKeepingQuoting(StepContext context, Map<String, String> values) async {
    if (values.values.any(_carriesQuote) && await context.files.exists(templatePath)) {
      final List<QuotingBroken> broken = quotingBrokenIn(
        await context.files.read(templatePath),
        values,
      );
      if (broken.isNotEmpty) {
        throw TemplateRefused(
          <String>[
            '$templatePath stands a slot inside quoting that the value fills it with would close, '
                'so the file this writes cannot be read back',
            ...broken.map((QuotingBroken each) => each.sentence),
            'nothing here escapes a value for the quoting it lands in: either the template writes '
                'the slot where no quoting is open, or the value is one without that character',
          ].join('; '),
        );
      }
    }
    return renderedWith(context, values);
  }
}

/// Whether [value] carries either character that closes quoting.
bool _carriesQuote(String value) => value.contains("'") || value.contains('"');
