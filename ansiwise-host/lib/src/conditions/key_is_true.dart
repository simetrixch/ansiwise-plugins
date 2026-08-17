import 'package:ansiwise_api/ansiwise_api.dart';

import '../steps/host/key_value_file.dart';

/// Whether a key in a `KEY=value` file holds true.
///
/// ONE condition, pointed at a file and a key by the installation that uses it, and registered under
/// whatever name that installation chose. The file shape is the tool-shaped thing this package is
/// allowed to know: `KEY=value`, one per line, what a shell sources and what
/// [KeyValueFile] is already the one reader of. Which file, which key and what the answer is called
/// are properties of one product, so they arrive as values on the installation's own configuration
/// and are named nowhere here.
///
/// **TRUE IS THE WORD `true`, AND FALSE IS THE WORD `false`. NOTHING ELSE IS EITHER.** After the
/// quoting and any trailing comment are taken off — which is how the shell reading the same file
/// sees the value — the two words are the whole of what this reads. `TRUE`, `yes`, `1` and `on` are
/// refused along with `ture`, and that is the point of the rule rather than an oversight in it.
///
/// The alternative was a forgiving set, and it loses on the case that matters. A set is a table an
/// operator has to know, and a value outside whichever table was chosen reads as FALSE — so a typed
/// `ture` switches a whole phase of an installation off, the run stays green, and the only trace is
/// one line in a record saying a condition did not hold. That is the failure this condition exists
/// to prevent, and it cannot be prevented by a longer table: every table has an outside. One
/// spelling can be stated in the refusal itself, which is what makes the mistake a sentence the
/// operator reads before the first step rather than a phase they discover missing afterwards.
///
/// **THREE THINGS ARE NOT AN ANSWER AND ARE REFUSED, NOT ANSWERED FALSE.** The file is not there;
/// the file carries no line assigning the key; the key is assigned something that is neither word,
/// the empty value included. In each of them the file said nothing about the machine, and answering
/// "it does not hold" would put words in its mouth — a step skipped for a reason nobody wrote down.
/// The refusal is [ConditionUnanswerable], and it names the path, the key and what stood there.
///
/// **A refusal here costs nothing, because it lands before the first step.** Every condition of a
/// program is measured once, before any step runs, so a run refused by this one has touched nothing
/// and there is no half-built machine to put back. It also means the file has to exist BEFORE the
/// program starts: a program that writes the file and then gates a later step on it cannot work,
/// because the answer was taken before that step existed.
final class KeyIsTrue implements Predicate {
  /// Asks whether [key] holds true in the file at [path].
  const KeyIsTrue({required this.path, required this.key, this.runAnswer});

  /// Builds the condition from what one installation told it.
  factory KeyIsTrue.fromValues(Arguments values) => KeyIsTrue(
    path: values.text('file'),
    key: values.text('key'),
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

  /// WHICH answer fills the slot in the path, or null where the path carries none.
  ///
  /// **The file an installation states itself in is named for its stage, and the stage is a suffix
  /// and never a folder.** A condition pointed at `configs/config.dev` is a condition that is right
  /// on exactly one installation and silently wrong on the next — it reads a file that is not
  /// there, and a condition that cannot be answered stops the run before it starts. Pointed at
  /// `configs/config.<stage>` with this naming `stage`, it is right on all of them.
  final String? runAnswer;

  /// [path] with the slot filled from [answers], or [path] itself where this row names no answer.
  String pathIn(Arguments answers) {
    final String? named = runAnswer;
    if (named == null) {
      return path;
    }
    return path.replaceAll('<$named>', answers.text(named));
  }

  /// The one value this reads as true.
  static const String yes = 'true';

  /// The one value this reads as false.
  static const String no = 'false';

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final String path = pathIn(context.answers);
    if (!await context.files.exists(path)) {
      throw ConditionUnanswerable(
        '$path is not on this machine, so nothing says whether $key is $yes or $no\n'
        'this condition was pointed at that file by the installation configuration, and the file '
        'has to be there before the run starts',
      );
    }

    // Read with no template beside it. The template is the surface the FILLING question is asked
    // against — has this key been answered yet, and may it be overwritten — and none of that is
    // asked here: this reads the value that stands in the file and nothing else.
    final KeyValueFile file = KeyValueFile(template: '', current: await context.files.read(path));
    final String? value = file.valueOf(key);

    if (value == null) {
      throw ConditionUnanswerable(
        '$path carries no line assigning $key, so nothing says whether it is $yes or $no\n'
        'a commented-out assignment is not one: write $key=$yes or $key=$no',
      );
    }
    if (value == yes) {
      return PredicateResult.holds('$path says $key is $yes');
    }
    if (value == no) {
      return PredicateResult.doesNotHold('$path says $key is $no');
    }
    if (value.isEmpty) {
      throw ConditionUnanswerable(
        '$path assigns $key nothing at all, so nothing says whether it is $yes or $no\n'
        'write $key=$yes or $key=$no',
      );
    }
    throw ConditionUnanswerable(
      '$path says $key="$value", and this condition reads exactly "$yes" or exactly "$no"\n'
      'no other spelling is read as either, so that a mistyped value stops the run here instead of '
      'switching off every step that waits on $key',
    );
  }
}
