import 'package:ansiwise_api/ansiwise_api.dart';

import '../steps/host/key_value_file.dart';
import 'key_is_true.dart';

/// Whether two keys of one `KEY=value` file carry the same value.
///
/// The second shape a condition over such a file takes, beside [KeyIsTrue]. Some facts an
/// installation gates on are not written down as a word at all — they are a RELATION between two
/// things that are written down. Whether the machine being installed is also the one that builds is
/// such a fact: nobody types it, and it follows from whether the address of the builder and the
/// address of this machine are the same address.
///
/// **WHY NOT A KEY HOLDING THAT ANSWER.** A file could carry the relation as its own key, and then
/// the operator states the same fact twice and the two can disagree — an address, and a word about
/// that address. A pair that disagrees is what an installation fails on later, and the failure names
/// neither of them. Reading the relation is the shape that makes the disagreement impossible to
/// write down.
///
/// **WHY NOT ONE CONDITION AND A NEGATION IN THE PROGRAM FILE.** A `not:` behind `when:` is an
/// operator, and an operator is the beginning of the language a program file may not become. So
/// there are two registered shapes, [KeysAgree.agreeing] and [KeysAgree.differing], and a program
/// row still writes one bare name.
///
/// The file shape is the tool-shaped thing this package is allowed to know. WHICH file and WHICH two
/// keys are properties of one product, so they arrive as values on the installation's own
/// configuration and are named nowhere here.
///
/// **THE COMPARISON IS THE WHOLE VALUE, EXACTLY.** After the quoting and any trailing comment are
/// taken off — which is how the shell reading the same file sees them — the two values are compared
/// as they stand. Nothing is trimmed, lowercased or otherwise made to match, for the same reason
/// [KeyIsTrue] reads exactly one spelling: every rule that makes two unequal things compare equal
/// has an edge, and an installation that took a branch because of an edge nobody wrote down is the
/// failure this exists to prevent.
///
/// **THREE THINGS ARE NOT AN ANSWER AND ARE REFUSED, NOT ANSWERED EITHER WAY.** The file is not
/// there; the file carries no line assigning one of the two keys; one of them is assigned nothing at
/// all. The third is the one worth naming: an empty value is not a value that differs from another,
/// it is a fact nobody stated, and answering "they differ" would turn an unanswered file into a
/// decision about the machine.
final class KeysAgree implements Predicate {
  /// Asks whether [first] and [second] carry the same value in the file at [path].
  ///
  /// [holdsWhenEqual] is which of the two registered shapes this is. It is not configuration and it
  /// never appears in a file: it is decided by which of the two names the installation bound.
  const KeysAgree({
    required this.path,
    required this.first,
    required this.second,
    required this.holdsWhenEqual,
    this.runAnswer,
  });

  /// The shape that holds where the two values are the same.
  factory KeysAgree.agreeing(Arguments values) => KeysAgree(
    path: values.text('file'),
    first: values.text('key'),
    second: values.text('other_key'),
    holdsWhenEqual: true,
    runAnswer: values.has('run_answer') ? values.text('run_answer') : null,
  );

  /// The shape that holds where the two values are not the same.
  factory KeysAgree.differing(Arguments values) => KeysAgree(
    path: values.text('file'),
    first: values.text('key'),
    second: values.text('other_key'),
    holdsWhenEqual: false,
    runAnswer: values.has('run_answer') ? values.text('run_answer') : null,
  );

  /// What either shape has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of an answer whose value fills the slot spelled with that same name in '
          'the path above. Leave it off where the file is named the same on every '
          'installation',
    ),
    ArgumentSpec(
      name: 'file',
      kind: ArgumentKind.text,
      describes: 'the KEY=value file this condition reads, as a path on the machine',
    ),
    ArgumentSpec(
      name: 'key',
      kind: ArgumentKind.text,
      describes: 'one of the two keys in that file whose values are compared',
    ),
    ArgumentSpec(
      name: 'other_key',
      kind: ArgumentKind.text,
      describes: 'the other of the two keys whose values are compared',
    ),
  ];

  /// The file this condition reads.
  final String path;

  /// WHICH answer fills the slot spelled the same way in [path], or null where it carries none.
  ///
  /// The file an installation states itself in is named for its stage, and the stage is a suffix and
  /// never a folder. Written out, this condition is right on one installation and reads a file that
  /// is not there on the next — and a condition that cannot be answered stops the run before it
  /// starts.
  final String? runAnswer;

  /// [path] with the slot filled from [answers], or [path] itself where this row names no answer.
  String pathIn(Arguments answers) {
    final String? named = runAnswer;
    if (named == null) {
      return path;
    }
    return path.replaceAll('<$named>', answers.text(named));
  }

  /// One of the two keys compared.
  final String first;

  /// The other of the two keys compared.
  final String second;

  /// Whether this shape holds when the two values are the same.
  final bool holdsWhenEqual;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final String path = pathIn(context.answers);
    if (!await context.files.exists(path)) {
      throw ConditionUnanswerable(
        '$path is not on this machine, so nothing says whether $first and $second carry the same '
        'value\n'
        'this condition was pointed at that file by the installation configuration, and the file '
        'has to be there before the run starts',
      );
    }

    // Read with no template beside it, for the reason KeyIsTrue reads it that way: the template is
    // the surface the FILLING question is asked against, and none of that is asked here.
    final KeyValueFile file = KeyValueFile(template: '', current: await context.files.read(path));

    final String left = _valueOf(file, first);
    final String right = _valueOf(file, second);
    final bool same = left == right;

    if (same == holdsWhenEqual) {
      return PredicateResult.holds(
        same
            ? '$path says $first and $second are both "$left"'
            : '$path says $first is "$left" and $second is "$right"',
      );
    }
    return PredicateResult.doesNotHold(
      same
          ? '$path says $first and $second are both "$left"'
          : '$path says $first is "$left" and $second is "$right"',
    );
  }

  /// The value of [key], or a refusal naming what the file said instead.
  String _valueOf(KeyValueFile file, String key) {
    final String? value = file.valueOf(key);
    if (value == null) {
      throw ConditionUnanswerable(
        '$path carries no line assigning $key, so nothing says whether $first and $second carry '
        'the same value\n'
        'a commented-out assignment is not one',
      );
    }
    if (value.isEmpty) {
      throw ConditionUnanswerable(
        '$path assigns $key nothing at all, so there is no value to compare it by\n'
        'an empty value is a fact nobody stated, and reading it as one that differs would turn an '
        'unanswered file into a decision about this machine',
      );
    }
    return value;
  }
}
