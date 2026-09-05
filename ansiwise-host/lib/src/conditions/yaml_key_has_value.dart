import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:yaml/yaml.dart';

import '../steps/host/yaml_file.dart';

/// Whether a key in a YAML file carries one stated value, addressed by a dotted path.
///
/// The same question `key_has_value` asks of a `KEY=value` file, asked of the other file grammar
/// this package reads. A `KEY=value` file is what a shell sources; a YAML file is what a declarative
/// tree is written in, and a product that declares its facts there has no way to gate a program row
/// on them without this. Which file, which path and which value are properties of one product, so
/// all three arrive as values on the installation's own configuration and are named nowhere here.
///
/// **THE PATH IS DOTTED, AND EACH SEGMENT IS ONE MAP LOOKUP.** `certificates.issuer.name` is three
/// lookups and nothing else: no index, no wildcard, no expression. A path that leaves the maps
/// before it runs out of segments names nothing, and that is a refusal rather than an answer.
///
/// **A SCALAR IS COMPARED AS THE FILE WROTE IT.** `3` reads as `"3"` and `true` reads as `"true"`,
/// so a row may gate on a number or on a boolean without the file having to quote it. The
/// alternative — refusing every scalar that is not a string — refuses the first key anybody would
/// gate on, because a declarative tree writes its switches unquoted.
///
/// **FOUR THINGS ARE NOT AN ANSWER AND ARE REFUSED, NOT ANSWERED EITHER WAY.** The file is not
/// there; the file does not parse; the path names nothing; the path names a list or a map. In each
/// of them the file said nothing this can compare, and answering "it does not hold" would put words
/// in its mouth — a phase switched off for a reason nobody wrote down.
///
/// **A KEY WRITTEN WITH NOTHING UNDER IT IS AN ANSWER.** `issuer:` with no value is a key the file
/// carries and does not fill, which is a fact about the file rather than a gap in it. It does not
/// hold, and the sentence says what stood there. This is the reading `key_has_value` already takes
/// for an empty assignment, and it matters for the same reason: the row that fills such a file is
/// the one a refusal would stop.
///
/// **TWO REGISTERED NAMES OVER ONE READING, and a program row still writes one bare word.** A row
/// acts where the value is the one it belongs to; another acts where it is not. Written as a
/// negation behind `stated_when:` that would be an operator, and an operator is where a program file
/// starts being a language. So there are [YamlKeyHasValue.matching] and [YamlKeyHasValue.differing],
/// exactly as the pairs beside this one are bound.
///
/// **A refusal here costs nothing, because it lands before the first step.** Every condition of a
/// program is measured once, before any step runs, so a run refused by this one has touched nothing.
/// It also means the file has to exist BEFORE the program starts: a program that writes the file and
/// then gates a later row on it cannot work, because the answer was taken before that row existed.
final class YamlKeyHasValue implements Predicate {
  /// Asks whether [key] carries [value] in the YAML file at [path].
  ///
  /// [holdsWhenEqual] is which of the two registered shapes this is. It is not configuration and it
  /// never appears in a file: it is decided by which of the two names the installation bound.
  const YamlKeyHasValue({
    required this.path,
    required this.key,
    required this.value,
    required this.holdsWhenEqual,
    this.runAnswer,
  });

  /// The shape that holds where the key carries the stated value.
  factory YamlKeyHasValue.matching(Arguments values) =>
      YamlKeyHasValue._from(values, holdsWhenEqual: true);

  /// The shape that holds where it carries anything else.
  factory YamlKeyHasValue.differing(Arguments values) =>
      YamlKeyHasValue._from(values, holdsWhenEqual: false);

  /// Builds either shape from what one installation told it.
  factory YamlKeyHasValue._from(Arguments values, {required bool holdsWhenEqual}) =>
      YamlKeyHasValue(
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
      describes: 'the YAML file this condition reads, as a path on the machine',
    ),
    ArgumentSpec(
      name: 'key',
      kind: ArgumentKind.text,
      describes:
          'the key in that file whose value decides this condition, as a dotted path — write '
          '"certificates.issuer.name" for the name under issuer under certificates. Each segment is '
          'one map lookup, and a path that leaves the maps names nothing',
    ),
    ArgumentSpec(
      name: 'value',
      kind: ArgumentKind.text,
      describes:
          'the value that key carries where this condition holds, compared as the file wrote it — '
          'a number or a boolean is read as the text of it, so an unquoted "true" in the file is '
          'matched by "true" here',
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

  /// The dotted path in it that decides.
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

    final YamlNode document;
    try {
      document = loadYamlNode(await context.files.read(path));
    } on YamlException catch (broken) {
      throw ConditionUnanswerable(
        '$path is not readable as YAML, so nothing says what $key carries\n'
        'repair the file: $broken',
      );
    }

    final YamlNode? at = yamlNodeAt(document, key);
    if (at == null) {
      throw ConditionUnanswerable(
        '$path carries nothing under $key, so nothing says whether it is "$value"\n'
        'the path is dotted and each segment is one key of a map: write the whole path from the '
        'top of the file',
      );
    }
    if (at.value is List || at.value is Map) {
      throw ConditionUnanswerable(
        '$path carries a list or a map under $key, and this condition compares one value\n'
        'point it at a key that holds a single value',
      );
    }

    final String carried = at.value == null ? '' : '${at.value}';
    final bool same = carried == value;
    final String said = carried.isEmpty ? 'nothing at all' : '"$carried"';
    return same == holdsWhenEqual
        ? PredicateResult.holds('$path says $key is $said, and this reads for "$value"')
        : PredicateResult.doesNotHold('$path says $key is $said, and this reads for "$value"');
  }
}
