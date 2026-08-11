import 'package:ansiwise_api/ansiwise_api.dart';

import 'master_part.dart';

/// Refuses a run whose role and master answers contradict each other, before anything else runs.
///
/// **What makes these two answers legal is a property of the PAIR.** A declaration is about one
/// answer: it can say that a role is one of two words and that a master is text, and it cannot say
/// that the second must be given exactly where the first says "slave". So the pair is measured here
/// instead, at the head of the program, where the answers are all this run has and no machine has
/// been asked anything.
///
/// **Both halves, and the message names both.** A cluster that does not hold the master part and
/// names no cluster that does has nowhere for its books, its secret store or its tailnet to be. A
/// cluster that holds the master part and also names another one has answered two things that cannot
/// both be true, and the name it gave reaches nothing that reads it.
///
/// **The rule itself is not here.** It is [MasterPart], which the steps writing the map and the
/// profile ask as well — so removing this row cannot make either of them accept a pair it refuses,
/// and no two of the three can come to state the rule differently. What this row adds is WHEN: the
/// refusal arrives before the branch is cut, rather than after a checkout has already been changed.
///
/// **It only measures.** Nothing about a machine decides its answer, so it costs nothing and stands
/// beside the other question that only this product can answer about its own run.
final class RequireMasterMatchesRole extends ObservingStep {
  /// Refuses a run whose two answers about the master part disagree.
  const RequireMasterMatchesRole();

  /// Builds the step from what the program gave it, which is nothing.
  ///
  /// It declares no argument: what it measures is a pair of ANSWERS of the run, and which answers
  /// those are, is this product's own rather than something a row varies.
  factory RequireMasterMatchesRole.fromArguments(Arguments arguments) =>
      const RequireMasterMatchesRole();

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// Taken from the rule rather than restated, so a program that stopped declaring one of them is
  /// refused before a run starts rather than leaving this gate reading an empty bag.
  static const List<String> answers = MasterPart.answers;

  @override
  Future<CheckResult> check(StepContext context) async {
    final MasterPart part = MasterPart.of(context.answers);
    final List<String> wrong = part.problems;
    if (wrong.isNotEmpty) {
      return CheckResult.blocked(
        'the two answers about the master part contradict each other: ${wrong.join('; ')}',
      );
    }
    // With the pair legal, a name given is a cluster this one belongs to and a name left out is a
    // cluster holding the master part — the two states the rule leaves, read off the same object.
    if (part.named case final String other) {
      return CheckResult.satisfied('this cluster belongs to $other, which holds the master part');
    }
    return const CheckResult.satisfied('this cluster holds the master part itself');
  }
}
