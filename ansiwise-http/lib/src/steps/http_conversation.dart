/// Holding one request-and-response exchange, in the protocol's own words.
///
/// **This package knows HTTP and never an application of it.** A method, an address, a header, a
/// body, a status and a field of a JSON answer are the protocol's own words; which address answers,
/// which field matters and which value means what are one program row's to say. Nothing in this
/// file carries a default that belongs to any one product.
///
/// **A credential rides `Authorization: Bearer`, and that is a decision about the record.** It is a
/// header name the framework's redactor removes on sight, so the value cannot reach the record even
/// on a run where nobody registered it as a secret. It is also not a process argument: no step of
/// this package starts a process at all, so no value here can reach a process listing.
///
/// **An answer that cannot be understood is never read as an empty one.** Reading a failure as
/// "nothing is there" is what makes a tool write over what IS there, so every reading here has a
/// third case that refuses, and the steps turn it into a blocked check rather than into work.
library;

import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

/// What one read of an address actually said, which is one of THREE things and not two.
///
/// The third case is the one that goes missing when a reading is built on a yes-or-no answer: a
/// gateway's own error page, a 500, a body of a shape nobody expected — none of those says what
/// stands at the address, and a step that takes any of them for "nothing there" acts on a state it
/// never saw.
sealed class HttpReading {
  const HttpReading();
}

/// The address answered that the path holds nothing, in the protocol's own word for it: 404.
final class NothingThere extends HttpReading {
  /// Says the path holds nothing.
  const NothingThere();
}

/// The address answered, and this is the JSON object it holds.
final class AnswerHeld extends HttpReading {
  /// Holds [object], the decoded body of the answer.
  const AnswerHeld(this.object);

  /// What the answer's body holds, as the address gave it.
  final Map<String, Object?> object;
}

/// The address answered something no step may act on.
final class Unreadable extends HttpReading {
  /// Could not be understood, [because].
  const Unreadable(this.because);

  /// What was wrong with the answer, in the words a refusal uses.
  final String because;
}

/// What [answer] says about [url], told apart into the three cases.
///
/// The body is decoded here rather than by each caller, because deciding that an answer is
/// understandable and deciding what it says are the same act: an answer whose body will not decode
/// is exactly the case that used to pass for empty.
HttpReading readingOf(HttpAnswer answer, {required String url}) {
  if (answer.status == 404) {
    return const NothingThere();
  }
  if (!answer.ok) {
    return Unreadable(
      'asking $url answered ${answer.status}, which says neither what stands there nor that '
      'nothing does',
    );
  }
  final Object? decoded = _decodedOrNull(answer.body);
  if (decoded is! Map<String, Object?>) {
    return Unreadable(
      'asking $url answered ${answer.status} with a body that is not a JSON object, so no field '
      'can be read out of it',
    );
  }
  return AnswerHeld(decoded);
}

Object? _decodedOrNull(String body) {
  if (body.trim().isEmpty) {
    return null;
  }
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// What one field of a decoded answer holds, told apart into the three cases a caller acts on.
sealed class FieldReading {
  const FieldReading();
}

/// The field holds exactly one value, carried as text.
final class FieldText extends FieldReading {
  /// Holds [value].
  const FieldText(this.value);

  /// The value, as text: a JSON string as it stands, a number or a boolean spelled out.
  final String value;
}

/// The named field is not in the answer, or holds nothing.
final class FieldMissing extends FieldReading {
  /// Says the answer carries no value under [field].
  const FieldMissing(this.field);

  /// The path that was asked for, as the row wrote it.
  final String field;
}

/// The field is there and does not hold one value.
final class FieldNotOneValue extends FieldReading {
  /// Cannot be carried as one value, [because].
  const FieldNotOneValue(this.because);

  /// What shape stood there instead, in the words a refusal uses.
  final String because;
}

/// The value [path] names inside [object].
///
/// The path is field names joined by dots, each descending one JSON object: `data.state` reads the
/// `state` field of the `data` object. That is the whole grammar — no index, no wildcard and no
/// expression, because a name standing for exactly one value is a mechanism and anything more is a
/// language a program file may not become.
FieldReading fieldIn(Map<String, Object?> object, String path) {
  Object? current = object;
  for (final String segment in path.split('.')) {
    if (current is! Map<String, Object?>) {
      return FieldNotOneValue(
        '"$path" descends into something that is not a JSON object, so "$segment" names nothing',
      );
    }
    if (!current.containsKey(segment)) {
      return FieldMissing(path);
    }
    current = current[segment];
  }
  return switch (current) {
    null => FieldMissing(path),
    final String text => FieldText(text),
    final num number => FieldText('$number'),
    final bool truth => FieldText('$truth'),
    _ => FieldNotOneValue(
      '"$path" holds a ${current is List<Object?> ? 'list' : 'object'}, not one value',
    ),
  };
}

/// Where one slot of a row's texts takes its value from.
///
/// **Two sources and no third.** An answer this run was started with, and a value that already
/// stands in the row. The second is not a third grammar: a row writes `{measured: <name>}`, and the
/// framework writes the carried value in over that body before the step is built — so what a
/// running step meets under that name is the value itself.
sealed class SlotSource {
  const SlotSource();
}

/// A slot filled from an answer this run holds.
final class SlotAnswer extends SlotSource {
  /// Binds a slot to the answer called [answer].
  const SlotAnswer(this.answer);

  /// The name of the answer, as the program declares it.
  final String answer;
}

/// A slot whose value stands in the row already.
final class SlotWritten extends SlotSource {
  /// Holds [value], the text that fills the slot.
  const SlotWritten(this.value);

  /// What fills the slot.
  final String value;
}

/// Where each slot of a row's texts takes its value from, read out of the row's `values` mapping.
///
/// **One named slot standing for exactly one value, and nothing that evaluates.** `slot-name:
/// {answer: name}` names an answer: the slot is spelled with hyphens where an answer is spelled
/// with underscores, and the grammar forbids mixing them on purpose so no name has two spellings —
/// which is why the answer is named outright rather than looked up by the slot's own name.
///
/// **`slot-name: {measured: name}` names a value that does not exist yet.** The row publishing it
/// has not run when a program is examined, so the entry stands for no value here and is left out —
/// a step that could not be built while the value is missing would refuse the whole program before
/// anything measured anything. By the time the row runs, the framework has written that value in
/// where the body stood, which is why a written-out value is read here and not refused.
Map<String, SlotSource> slotSources(Object? declared) {
  if (declared == null) {
    return const <String, SlotSource>{};
  }
  if (declared is! Map<String, Object?>) {
    throw ArgumentError.value(
      declared,
      'values',
      'is a mapping of slot-name to {answer: name} or {measured: name}',
    );
  }
  final Map<String, SlotSource> sources = <String, SlotSource>{};
  for (final MapEntry<String, Object?> entry in declared.entries) {
    final Object? body = entry.value;
    if (body case final String written) {
      sources[entry.key] = SlotWritten(written);
      continue;
    }
    if (body is Map<String, Object?> && body.keys.length == 1) {
      if (body['answer'] case final String answer) {
        sources[entry.key] = SlotAnswer(answer);
        continue;
      }
      if (body['measured'] is String) {
        continue;
      }
    }
    throw ArgumentError.value(
      body,
      entry.key,
      'is bound as {answer: name} or {measured: name} and nothing else',
    );
  }
  return sources;
}

/// The slot values this run holds for [sources], or the refusal that stops the row.
///
/// Refused rather than left empty: a slot whose answer nobody holds would stay in the text as its
/// own seven literal characters, and whatever reads the request next would take them as content.
({Map<String, String>? filled, String? refusal}) slotValues(
  StepContext context,
  Map<String, SlotSource> sources,
) {
  final Map<String, String> filled = <String, String>{};
  for (final MapEntry<String, SlotSource> each in sources.entries) {
    switch (each.value) {
      case SlotWritten(:final String value):
        filled[each.key] = value;
      case SlotAnswer(:final String answer):
        if (!context.answers.has(answer)) {
          return (
            filled: null,
            refusal:
                'this run holds no answer called "$answer", and it is what fills "<${each.key}>" '
                '— the program has to declare an answer of that name for the operator to be asked '
                'for one',
          );
        }
        filled[each.key] = context.answers.text(answer);
    }
  }
  return (filled: filled, refusal: null);
}

/// Why the declared slots do not fit [texts], or null when every one lands somewhere.
///
/// A slot named in the mapping and spelled in none of the row's texts is a value that goes nowhere:
/// the row runs, ignores it, and reports success — which is the quiet defect a refusal by name
/// prevents.
String? unusedSlotRefusal(Map<String, String> filled, Iterable<String?> texts) {
  for (final String slot in filled.keys) {
    final bool used = texts.any((String? text) => text != null && text.contains('<$slot>'));
    if (!used) {
      return 'the values mapping names "<$slot>" and no text of this row spells that slot, so the '
          'value would go nowhere while looking used';
    }
  }
  return null;
}

/// Why [url] cannot be sent as it stands, or null when it can.
///
/// Anything still between angle brackets is a slot nothing filled — including a misspelling the
/// slot grammar would not accept, which is exactly what a misspelled slot looks like. Judged on the
/// address alone: a body is another interface's arbitrary content, where angle brackets can be
/// legitimate, so a caller fills its declared slots there and judges nothing else.
String? leftoverSlotRefusal(String url) {
  final String? slot = leftoverSlotIn(url);
  return slot == null
      ? null
      : '$url still carries $slot, and nothing filled it — name the answer that fills it in the '
            'values mapping, or write the address out whole';
}

/// The socket file this row's requests go to with every slot of it filled, or the refusal that
/// stops the row.
///
/// **A path is filled the way an address is, and for the same reason.** Where a socket file stands
/// is a fact of ONE machine — a directory something else on it chose, and often one carrying a name
/// nobody wrote down — so a program file that shipped one written out would be right on the
/// installation it was written against and wrong on every other. The row spells a slot and the run
/// fills it, exactly as it does for the address.
///
/// Null for [socketPath] answers null: a row that names no socket file sends over the network, and
/// there is nothing here to fill or refuse.
({String? path, String? refusal}) filledSocketPath(String? socketPath, Map<String, String> filled) {
  if (socketPath == null) {
    return (path: null, refusal: null);
  }
  final String path = filledSlots(socketPath, filled);
  if (leftoverSlotIn(path) case final String slot) {
    return (
      path: null,
      refusal:
          '$path still carries $slot, and nothing filled it — name the answer that fills it in the '
          'values mapping, or write the socket file out whole',
    );
  }
  return (path: path, refusal: null);
}

/// The value of the answer named by [answerName], or why it cannot ride a header.
///
/// The name comes from the row and the value from this run, so a missing answer is refused with
/// both names in the sentence rather than sent as an empty header the other end reads as anonymous.
({String? value, String? refusal}) answerValue(
  StepContext context,
  String? answerName, {
  required String carries,
}) {
  if (answerName == null) {
    return (value: null, refusal: null);
  }
  if (!context.answers.has(answerName)) {
    return (
      value: null,
      refusal:
          'this run holds no answer called "$answerName", and it is $carries — the program has to '
          'declare an answer of that name for the operator to be asked for one',
    );
  }
  final String value = context.answers.text(answerName);
  if (value.isEmpty) {
    return (
      value: null,
      refusal: '"$answerName" was answered with nothing, so $carries would be sent empty',
    );
  }
  return (value: value, refusal: null);
}

/// The bearer credential this row's requests carry, from whichever of the two sources it names.
///
/// **Two sources, because a credential reaches a row two ways and only two.** It comes from the
/// operator, and then the row names the ANSWER it was given under and no file carries the value; or
/// it did not exist when the run started, and then it comes from a measurement an earlier row
/// published — an argument declared secret, which the framework fills and which only a measurement
/// declared secret may fill. The second is the whole of a handshake: what a row gets back from one
/// exchange is what the next request has to prove itself with.
///
/// **Naming both is refused rather than resolved.** A precedence between two credentials is a rule
/// a reader has to know before they can tell which one a request carried, and a row that meant the
/// other one would look exactly the same.
({String? value, String? refusal}) bearerCredential(
  StepContext context, {
  required String? answerName,
  required String? given,
  required String carries,
}) {
  // GIVEN AND EMPTY IS NOT THE SAME AS NOT GIVEN. A measurement filling this argument answered, and
  // what it answered was nothing — a request sent without the header would go out unauthenticated on
  // the strength of an empty answer, and the other end's refusal would be read as a fault of the
  // address. An operator answer is refused the same way one line below.
  if (given != null && given.isEmpty) {
    return (
      value: null,
      refusal:
          'the value filling "bearer" is empty, so there is nothing to carry — a request sent '
          'without the header is not the same request',
    );
  }
  final bool written = given != null && given.isNotEmpty;
  if (answerName != null && written) {
    return (
      value: null,
      refusal:
          'this row names "bearer_answer" and fills "bearer" as well, and nothing says which of the '
          'two rides the header — name one of them',
    );
  }
  if (written) {
    return (value: given, refusal: null);
  }
  return answerValue(context, answerName, carries: carries);
}

/// The headers one row's request carries: a credential and a body's declared type, nothing else.
Map<String, String> composedHeaders({String? bearer, String? contentType}) => <String, String>{
  if (bearer != null) 'authorization': 'Bearer $bearer',
  'content-type': ?contentType,
};
