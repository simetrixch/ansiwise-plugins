import 'package:ansiwise_core/ansiwise_core.dart';

/// Whether two answers of one run carry the same value.
///
/// **The third shape a condition takes here, and the first that reads the RUN rather than a file.**
/// Some facts an installation gates on are not written down anywhere on the machine: they are a
/// relation between two things the run was told. Whether the machine being installed is also the one
/// that builds is such a fact — nobody types it, and it follows from whether the address of the
/// builder and the address of this machine are the same address.
///
/// **WHY NOT READ IT OUT OF A FILE, WHICH IS WHAT THE OTHER TWO DO.** A file is written by a step,
/// and a step runs after the answers are validated. So a condition that has to be true BEFORE the
/// first step — the one deciding whether an answer had to be given at all — cannot wait for a file
/// that does not exist yet. That is the case this exists for, and the only one.
///
/// **WHY NOT A COMPARISON WRITTEN INTO THE PROGRAM FILE.** A row saying
/// `stated_when: {answer: build_plane, equals_answer: fqdn}` puts a condition in a file beside the
/// registered ones — and the moment a file can compare, it can compare anything. Registered, the
/// comparison is a class with a probe, and the file writes one bare name.
///
/// **WHY NOT ONE CONDITION AND A NEGATION.** A `not:` in a program file is an operator, and an
/// operator is the beginning of the language a program file may not become. So there are two
/// registered shapes, [AnswersAgree.agreeing] and [AnswersAgree.differing].
///
/// WHICH two answers is a property of one product and arrives as values on the installation's own
/// configuration. This package names neither.
///
/// **AN ANSWER NOBODY GAVE IS NOT AN ANSWER THAT DIFFERS.** Where either side is absent this refuses
/// rather than deciding, for the reason the file-reading shapes refuse an unassigned key: answering
/// "they differ" would turn a question nobody answered into a decision about the installation.
final class AnswersAgree implements Predicate {
  /// Asks whether [first] and [second] hold the same value in the run.
  ///
  /// [holdsWhenEqual] is which of the two registered shapes this is. It is not configuration and it
  /// never appears in a file: it is decided by which of the two names the installation bound.
  const AnswersAgree({required this.first, required this.second, required this.holdsWhenEqual});

  /// The shape that holds where the two values are the same.
  factory AnswersAgree.agreeing(Arguments values) => AnswersAgree(
    first: values.text('answer'),
    second: values.text('other_answer'),
    holdsWhenEqual: true,
  );

  /// The shape that holds where the two values are not the same.
  factory AnswersAgree.differing(Arguments values) => AnswersAgree(
    first: values.text('answer'),
    second: values.text('other_answer'),
    holdsWhenEqual: false,
  );

  /// What either shape has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'answer',
      kind: ArgumentKind.answerName,
      describes: 'one of the two answers whose values are compared',
    ),
    ArgumentSpec(
      name: 'other_answer',
      kind: ArgumentKind.answerName,
      describes: 'the other of the two answers whose values are compared',
    ),
  ];

  /// One of the two answers compared.
  final String first;

  /// The other of the two.
  final String second;

  /// Whether this shape holds where the two are equal.
  final bool holdsWhenEqual;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final String left = _valueOf(context, first);
    final String right = _valueOf(context, second);
    final bool same = left == right;

    final String because = same
        ? '$first and $second are both "$left"'
        : '$first is "$left" and $second is "$right"';
    return same == holdsWhenEqual
        ? PredicateResult.holds(because)
        : PredicateResult.doesNotHold(because);
  }

  /// What [name] holds in this run, refusing where nobody answered it.
  String _valueOf(PredicateContext context, String name) {
    if (!context.answers.has(name)) {
      throw ConditionUnanswerable(
        'this run holds no answer called "$name", so nothing says whether it and the other are the '
        'same\n'
        'this condition was pointed at that answer by the installation configuration, and a '
        'condition that cannot be answered stops the run before it starts',
      );
    }
    final String value = context.answers.text(name);
    if (value.isEmpty) {
      throw ConditionUnanswerable(
        '"$name" was answered with nothing, and an answer nobody gave is not one that differs from '
        'another — deciding either way here would turn a question nobody answered into a decision '
        'about this installation',
      );
    }
    return value;
  }
}
