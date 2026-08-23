/// Reading one value out of a settings file of this machine, and filling the slot such a path may
/// carry.
///
/// **Two steps of this package read the same file the same way.** One reads which repository a
/// checkout is cloned from and the credential it is read with; the other reads the credential a
/// push from that checkout is made with. Both are `KEY=value` files an earlier program of the same
/// installation wrote, and both are pointed at them by a path that may still carry a slot standing
/// for an answer of the run.
///
/// **A second copy would drift on the rule that decides an address.** The three rules below —
/// a missing file is no value, an empty value is no value, and a value still wearing angle brackets
/// is the text that MARKS it unfilled and is refused like an absent one — are what stop a
/// placeholder becoming part of a remote address or of a stored credential. A copy of them is a
/// copy somebody has to keep in step, and the day the copies disagree the two steps read the same
/// file and answer differently about it.
///
/// It is not exported from this package's public library. What a program row names is a step, and
/// these are two functions the steps of this package share.
library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// The value [file] records under [key], or null where it records none worth reading.
///
/// The file is `KEY=value` lines, which is the shape the settings files of an installation are
/// written in. A value still carrying angle brackets is the text that marks it unfilled, and it is
/// refused like an absent one: sent onward it would become part of an address.
///
/// [elevated] is the reading account, and it is required rather than defaulted so that a caller
/// carrying the elevation a row granted cannot drop it here without the compiler saying so.
Future<String?> recordedValue(
  StepContext context,
  String file,
  String key, {
  required bool elevated,
}) async {
  if (!await context.files.exists(file, elevated: elevated)) {
    return null;
  }
  final String content = await context.files.read(file, elevated: elevated);
  final RegExp line = RegExp('^[ \\t]*${RegExp.escape(key)}[ \\t]*=[ \\t]*(.*)\$');
  for (final String each in content.split('\n')) {
    final RegExpMatch? match = line.firstMatch(each.trimRight());
    if (match == null) {
      continue;
    }
    String value = match.group(1)!.trim();
    if (value.length >= 2 &&
        (value.startsWith('"') && value.endsWith('"') ||
            value.startsWith("'") && value.endsWith("'"))) {
      value = value.substring(1, value.length - 1);
    }
    if (value.isEmpty || (value.contains('<') && value.contains('>'))) {
      return null;
    }
    return value;
  }
  return null;
}

/// [text] with the run's own value in its slot, or null while a slot stands unfilled.
///
/// [runAnswer] is the name of the answer whose value fills the slot spelled with that same name, or
/// null where the row named none. A text still carrying a slot afterwards is refused rather than
/// sent, because a path with `<something>` in it names a file nobody has.
String? filledPath(StepContext context, String text, String? runAnswer) {
  String written = text;
  if (runAnswer case final String name) {
    if (context.answers.optionalText(name) case final String value) {
      written = filledSlots(written, <String, String>{name: value});
    }
  }
  return leftoverSlotIn(written) == null ? written : null;
}
