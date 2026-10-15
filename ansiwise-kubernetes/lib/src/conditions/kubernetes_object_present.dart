import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubernetes_object_absent.dart';

/// Whether one named object stands in the cluster: [KubernetesObjectAbsent] read the other way.
///
/// It lets a row act only where an earlier run already put something on the cluster. The question
/// asked and every refusal are that condition's, so the two can never disagree about one object: an
/// unreachable cluster stops the run, and a kind the cluster does not serve stands nowhere.
final class KubernetesObjectPresent implements Predicate {
  /// Asks whether the object [absent] names stands.
  const KubernetesObjectPresent(this.absent);

  /// Builds the condition from what one installation told it.
  factory KubernetesObjectPresent.fromArguments(Arguments values) =>
      KubernetesObjectPresent(KubernetesObjectAbsent.fromArguments(values));

  /// What this condition has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = KubernetesObjectAbsent.arguments;

  /// The reading this condition turns over.
  final KubernetesObjectAbsent absent;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final PredicateResult reading = await absent.evaluate(context);
    return reading.held
        ? PredicateResult.doesNotHold(reading.because)
        : PredicateResult.holds(reading.because);
  }
}
