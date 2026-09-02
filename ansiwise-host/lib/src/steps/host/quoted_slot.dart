/// The slots of a template that stand INSIDE quoting, and the values that would end it there.
///
/// **What breaks, and with a value nobody would call wrong.** A template is filled by substituting
/// text, so a slot standing inside a quoted run of text silently hands the value a job nobody gave
/// it: not carrying the character that closes that quoting. `to: '<recipients>'` filled with a
/// mailbox whose local part carries an apostrophe — `o'brien@example.com`, an ordinary address —
/// writes `to: 'o'brien@example.com'`, where the quoting the template opened ends four characters
/// early and everything after it is read as something nobody wrote.
///
/// **The failure lands nowhere near the value.** Measured against
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
/// **A row may say how its file escapes, and then a value is made to fit.** The template already
/// says WHICH quoting a slot stands inside — this scan reads it there. What a template cannot say is
/// how that quote is written inside itself, because that is the grammar of the file and this package
/// deliberately does not know which grammar it is writing. So the ROW says it, as `escaping:`, and
/// the two conventions every grammar this platform writes uses are the two it accepts: `doubled`,
/// where `'` inside single quoting is written `''` (YAML, SQL), and `backslash`, where `\` and `"`
/// are each preceded by one (JSON, YAML's double quoting, C).
///
/// **A row that says nothing is still REFUSED**, which is what keeps this from becoming a silent
/// path to a broken file: escaping happens only where somebody wrote down how this file escapes.
///
/// **And a value standing in two different quotings is refused even then.** One value is filled into
/// every slot of its name at once, so escaping it for single quoting would corrupt the occurrence
/// standing in double quoting or in none. Nothing here can make one text fit two contexts, and
/// saying so is better than picking one of them.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// How the file a row writes says a quote character that is part of a value.
///
/// **Two, because two is what the grammars this platform writes use.** A third would be a guess
/// about a file nobody here has written yet, and the row that meets it can say so then.
enum Escaping {
  /// The quote is written twice: `o'brien` inside single quoting becomes `o''brien`.
  ///
  /// YAML's single-quoted scalars and SQL's string literals. Nothing else in the value changes — a
  /// backslash inside single quoting is an ordinary character to both.
  doubled,

  /// A backslash is put in front of the quote, and in front of any backslash already there.
  ///
  /// JSON, YAML's double-quoted scalars, C. THE BACKSLASH IS ESCAPED FIRST: doing it the other way
  /// round would put a backslash in front of the backslash this escaping had just added, and the
  /// quote would close after all.
  backslash;

  /// The name a program row writes, which is this constant's own.
  static Escaping? named(String? word) => switch (word) {
    'doubled' => Escaping.doubled,
    'backslash' => Escaping.backslash,
    _ => null,
  };

  /// [value] with every [quote] in it written the way this convention writes one.
  String applied(String value, String quote) => switch (this) {
    Escaping.doubled => value.replaceAll(quote, quote * 2),
    Escaping.backslash => value.replaceAll(r'\', r'\\').replaceAll(quote, '\\$quote'),
  };
}

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
  Future<String> renderedKeepingQuoting(
    StepContext context,
    Map<String, String> values, {
    Escaping? escaping,
  }) async {
    if (!values.values.any(_carriesQuote) || !await context.files.exists(templatePath)) {
      return renderedWith(context, values);
    }

    final String text = await context.files.read(templatePath);
    final List<QuotingBroken> broken = quotingBrokenIn(text, values);
    if (broken.isEmpty) {
      return renderedWith(context, values);
    }

    // NOTHING IS ESCAPED WHERE NOBODY SAID HOW. The template says which quoting a slot stands
    // inside; what it cannot say is how this file writes that character inside itself, because that
    // is the grammar of the file. A row that did not say it gets the refusal it got before.
    if (escaping == null) {
      throw TemplateRefused(
        <String>[
          '$templatePath stands a slot inside quoting that the value fills it with would close, '
              'so the file this writes cannot be read back',
          ...broken.map((QuotingBroken each) => each.sentence),
          'this row says no escaping, so nothing here may change the value: write escaping: '
              'doubled where this file writes a quote twice, or escaping: backslash where it puts '
              'one in front — or move the slot out of the quoting, or answer a value without that '
              'character',
        ].join('; '),
      );
    }

    // ONE VALUE FILLS EVERY SLOT OF ITS NAME, so a name standing in two different quotings cannot
    // be made to fit both at once. That is refused by name rather than escaped for whichever
    // occurrence happened to be found first.
    final Map<String, Set<String?>> everywhere = quotingOfEachSlot(text);
    final List<String> ambiguous = <String>[
      for (final QuotingBroken each in broken)
        if ((everywhere[_nameOf(each.slot)] ?? const <String?>{}).length > 1)
          '${each.slot} stands in more than one quoting in this template',
    ];
    if (ambiguous.isNotEmpty) {
      throw TemplateRefused(
        <String>[
          '$templatePath fills one value into slots standing in different quotings, and one text '
              'cannot be escaped for both',
          ...{...ambiguous},
          'give each context its own slot name, or move the value out of the quoting it does not '
              'belong in',
        ].join('; '),
      );
    }

    // Escaped for the quoting each name stands in, which by now is exactly one.
    final Map<String, String> fitted = <String, String>{
      ...values,
      for (final QuotingBroken each in broken)
        _nameOf(each.slot): escaping.applied(values[_nameOf(each.slot)]!, each.quote),
    };
    return renderedWith(context, fitted);
  }
}

/// Which quotings each slot name of [text] stands inside, across every occurrence of it.
///
/// **One value fills every slot of its name at once**, so this is what decides whether escaping is
/// possible at all: a name standing once inside single quoting can be escaped for it, and a name
/// standing once inside single quoting and once inside none cannot — escaping it would corrupt the
/// second occurrence, and leaving it would break the first.
///
/// A null in the set is an occurrence standing inside no quoting.
Map<String, Set<String?>> quotingOfEachSlot(String text) {
  final Map<String, Set<String?>> found = <String, Set<String?>>{};
  final List<String> lines = text.split('\n');
  for (final String line in lines) {
    for (final RegExpMatch match in slotPattern.allMatches(line)) {
      found.putIfAbsent(match.group(1)!, () => <String?>{}).add(_quotingAt(line, match.start));
    }
  }
  return found;
}

/// The answer name inside a slot mark, so `<recipients?>` answers `recipients`.
String _nameOf(String slot) => slotPattern.firstMatch(slot)!.group(1)!;

/// Whether [value] carries either character that closes quoting.
bool _carriesQuote(String value) => value.contains("'") || value.contains('"');
