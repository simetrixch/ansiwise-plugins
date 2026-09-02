import 'package:ansiwise_core/ansiwise_core.dart';

import '../steps/host/key_value_file.dart';

/// Whether a key in a `KEY=value` file carries one stated value.
///
/// The third shape a condition over such a file takes, beside the one that reads a key as true or
/// false and the one that compares two keys. Some facts an installation gates on are neither a
/// truth nor a relation: they are a CHOICE among named things, and the name is the fact. Which
/// authority a cluster issues its certificates from is such a fact — the operator does not assert
/// that certificates are "on", they name the authority, and every row that acts on that choice asks
/// whether the name is the one it belongs to.
///
/// **WHY NOT A BOOLEAN BESIDE THE NAME.** A switch saying whether an authority is public while a
/// name says which one is two things that cannot be kept in step. Measured on a real machine: the
/// switch was turned on, the object under the one name was rewritten from the cluster's own
/// authority to the public one, and not a single certificate was re-issued — because the
/// certificate service watches the NAME a certificate references and never the specification behind
/// it. A cluster then served certificates signed by an authority the same run had deleted, and
/// every application went on reporting itself healthy. A name that IS the choice cannot drift from
/// it.
///
/// **THE VALUE IS STATED BY THE BINDING, NOT BY A SECOND KEY.** `keys_compare` exists for facts that
/// are a relation between two things an operator wrote; this is not one. The value here belongs to
/// the PRODUCT — one of the names its own programs write — so it stands in the installation's
/// configuration beside the file and the key, as a named slot holding exactly one value. Reading it
/// out of a second key would let an operator state the product's own vocabulary, and disagree with it.
///
/// **TWO REGISTERED NAMES OVER ONE READING, and a program row still writes one bare word.** A row
/// acts where the name is the one it belongs to; another acts where it is not. Written as a negation
/// behind `when:` that would be an operator, and an operator is where a program file starts being a
/// language. So there are [KeyHasValue.matching] and [KeyHasValue.differing], exactly as the two
/// pairs beside this one are bound.
///
/// **THE COMPARISON IS THE WHOLE VALUE, EXACTLY.** After the quoting and any trailing comment are
/// taken off — which is how the shell reading the same file sees it — the value is compared as it
/// stands. Nothing is trimmed further, lowercased or otherwise made to match: every rule that makes
/// two unequal things compare equal has an edge, and an installation that took a branch because of an
/// edge nobody wrote down is the failure this exists to prevent.
///
/// **TWO THINGS ARE NOT AN ANSWER AND ARE REFUSED, NOT ANSWERED EITHER WAY.** The file is not there,
/// and the file carries no line assigning the key. An empty value is NOT among them: a key assigned
/// nothing is a key that does not carry the stated value, which is a fact about the file rather than
/// a gap in it — and the row that fills such a file is the one that would otherwise never run.
///
/// **A refusal here costs nothing, because it lands before the first step.** Every condition of a
/// program is measured once, before any step runs, so a run refused by this one has touched nothing.
/// It also means the file has to exist BEFORE the program starts: a program that writes the file and
/// then gates a later row on it cannot work, because the answer was taken before that row existed.
final class KeyHasValue implements Predicate {
  /// Asks whether [key] carries [value] in the file at [path].
  ///
  /// [holdsWhenEqual] is which of the two registered shapes this is. It is not configuration and it
  /// never appears in a file: it is decided by which of the two names the installation bound.
  const KeyHasValue({
    required this.path,
    required this.key,
    required this.value,
    required this.holdsWhenEqual,
    this.runAnswer,
  });

  /// The shape that holds where the key carries the stated value.
  factory KeyHasValue.matching(Arguments values) => KeyHasValue._from(values, holdsWhenEqual: true);

  /// The shape that holds where it carries anything else.
  factory KeyHasValue.differing(Arguments values) =>
      KeyHasValue._from(values, holdsWhenEqual: false);

  /// Builds either shape from what one installation told it.
  factory KeyHasValue._from(Arguments values, {required bool holdsWhenEqual}) => KeyHasValue(
    path: values.text('file'),
    key: values.text('key'),
    value: values.text('value'),
    holdsWhenEqual: holdsWhenEqual,
    runAnswer: values.has('run_answer') ? values.text('run_answer') : null,
  );

  /// What this condition has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'file',
      kind: ArgumentKind.text,
      describes: 'the KEY=value file this condition reads, as a path on the machine',
    ),
    ArgumentSpec(
      name: 'key',
      kind: ArgumentKind.text,
      describes: 'the key in that file whose value decides this condition',
    ),
    ArgumentSpec(
      name: 'value',
      kind: ArgumentKind.text,
      describes:
          'the value that key carries where this condition holds. It belongs to the product — one '
          'of the names its own programs write — which is why it is stated here rather than read '
          'out of a second key an operator could disagree with',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of an answer whose value fills the slot spelled with that same name in the '
          'path above — write "stage" here and a "<stage>" in the path is filled with the stage '
          'this run holds. Without it the path is taken as it stands, which is right for a file '
          'whose name is the same on every installation',
    ),
  ];

  /// The file this condition reads.
  final String path;

  /// The key in it that decides.
  final String key;

  /// The value that key carries where this condition holds.
  final String value;

  /// Whether this shape holds on equality or on everything else.
  final bool holdsWhenEqual;

  /// WHICH answer fills the slot in the path, or null where the path carries none.
  final String? runAnswer;

  /// [path] with the slot filled from [answers], or [path] itself where this row names no answer.
  String pathIn(Arguments answers) {
    final String? named = runAnswer;
    if (named == null) {
      return path;
    }
    return path.replaceAll('<$named>', answers.text(named));
  }

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final String path = pathIn(context.answers);
    if (!await context.files.exists(path)) {
      throw ConditionUnanswerable(
        '$path is not on this machine, so nothing says what $key carries\n'
        'this condition was pointed at that file by the installation configuration, and the file '
        'has to be there before the run starts',
      );
    }

    // Read with no template beside it, for the reason the readings beside this one read it that
    // way: the template is the surface the FILLING question is asked against, and none of that is
    // asked here — this reads the value that stands in the file and nothing else.
    final KeyValueFile file = KeyValueFile(template: '', current: await context.files.read(path));
    final String? carried = file.valueOf(key);

    if (carried == null) {
      throw ConditionUnanswerable(
        '$path carries no line assigning $key, so nothing says whether it is "$value"\n'
        'a commented-out assignment is not one: write $key=<a value>',
      );
    }

    final bool same = carried == value;
    final String said = carried.isEmpty ? 'nothing at all' : '"$carried"';
    return same == holdsWhenEqual
        ? PredicateResult.holds('$path says $key is $said, and this reads for "$value"')
        : PredicateResult.doesNotHold('$path says $key is $said, and this reads for "$value"');
  }
}
