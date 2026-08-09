/// Every entry of a registry, as the running program sees it.
///
/// What a check cannot get from the TEXT of the registry file is the CLASS an entry builds. The
/// entry holds a factory function, and a function has no name to grep for; the class it returns is
/// known only once it has been called. So this calls it and reports the class of what came back
/// beside the `source` the entry claims — which is what lets a check hold the two against each
/// other, and against the file on disk.
///
/// Reading a class name off a live object is why this belongs in a test rather than in a compiled
/// program: `dart test` runs on the VM, and an ahead-of-time build is entitled to give those names
/// away — this would then report a name nobody wrote.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

import 'finding.dart';
import 'step_under_probe.dart';

/// Which of the three kinds a step declared itself to be.
enum StepKind {
  /// It changed something and can put it back.
  reversible,

  /// It cannot be taken back, and it says what is lost.
  irreversible,

  /// It only measures.
  observing,

  /// It extends [Step] itself, so nothing says whether it can be taken back.
  ///
  /// Not reachable while [Step]'s constructor is private, and written out because that is exactly
  /// what a check is for: the day the constructor stops being private, an entry answers this and the
  /// check reading it goes red, instead of the choice quietly gaining a fourth meaning.
  unknown,
}

/// One registry entry, with what only a running program can say about it.
final class RegistryEntry {
  /// Records what one entry of the registry turned out to be.
  const RegistryEntry({
    required this.name,
    required this.source,
    required this.className,
    required this.kind,
    required this.irreversibleReason,
  });

  /// The name a program file writes.
  final String name;

  /// Where the entry says its class is declared, as `path:line` relative to the repository root.
  final String source;

  /// The class the entry's factory actually built.
  final String className;

  /// Which of the three kinds the built step is.
  final StepKind kind;

  /// What about the change cannot be taken back, or the empty string when the question does not
  /// arise.
  final String irreversibleReason;
}

/// One predicate entry, as the registry holds it.
final class PredicateEntry {
  /// Records one predicate of the registry.
  const PredicateEntry({
    required this.name,
    required this.source,
    required this.className,
    required this.describes,
  });

  /// The name a program file writes behind `when:`.
  final String name;

  /// Where the predicate is declared, as `path:line` relative to the repository root.
  final String source;

  /// The class the registered instance turned out to be.
  ///
  /// A predicate is registered as one instance rather than as a factory, so several entries share a
  /// class and therefore a source: `vault_enabled` and `idp_enabled` are both `StageToggle` with
  /// different keys. The class is what says which declaration their source must point at.
  final String className;

  /// What it asks about the machine, in one line, for the plan the operator reads.
  final String describes;
}

/// A whole registry, read by building every entry in it.
final class RegistryReading {
  const RegistryReading._({
    required this.entries,
    required this.predicates,
    required this.problems,
  });

  /// Builds every entry of [registry] and reports what came back.
  factory RegistryReading.of(Registry registry) {
    final List<RegistryEntry> entries = <RegistryEntry>[];
    final List<PredicateEntry> predicates = <PredicateEntry>[];
    final List<Finding> problems = <Finding>[];

    for (final MapEntry<StepName, RegisteredStep> pair in registry.steps.entries) {
      final RegisteredStep entry = pair.value;

      // The key and the entry's own name are two places one name is written, and nothing but this
      // compares them. A program file writes the KEY and the record reports the NAME, so a pair that
      // disagrees sends an operator to a step nobody ran.
      if (pair.key.value != entry.name.value) {
        problems.add(
          Finding(
            pair.key.value,
            'the registry files "${entry.name.value}" under this key, so a program writing one name '
            'runs a step recorded under the other',
          ),
        );
      }

      final Step? step = buildStep(entry, problems.add);
      if (step == null) {
        continue;
      }

      entries.add(
        RegistryEntry(
          name: entry.name.value,
          source: entry.source,
          className: step.runtimeType.toString(),
          kind: _kindOf(step),
          irreversibleReason: _reasonOf(step, problems.add),
        ),
      );
    }

    for (final MapEntry<PredicateName, RegisteredPredicate> pair in registry.predicates.entries) {
      final RegisteredPredicate entry = pair.value;
      if (pair.key.value != entry.name.value) {
        problems.add(
          Finding(pair.key.value, 'the registry files the predicate "${entry.name.value}" here'),
        );
      }
      predicates.add(
        PredicateEntry(
          name: entry.name.value,
          source: entry.source,
          className: entry.predicate.runtimeType.toString(),
          describes: entry.describes,
        ),
      );
    }

    return RegistryReading._(entries: entries, predicates: predicates, problems: problems);
  }

  /// Every step the registry holds, in the order it holds them.
  final List<RegistryEntry> entries;

  /// Every predicate the registry holds.
  final List<PredicateEntry> predicates;

  /// What could not be read at all.
  ///
  /// An entry that could not be built has not been shown to be anything, and counting it as measured
  /// is the failure these checks exist to catch.
  final List<Finding> problems;

  /// The class names the registry builds.
  Set<String> get classNames => <String>{
    for (final RegistryEntry entry in entries) entry.className,
  };
}

StepKind _kindOf(Step step) => switch (step) {
  ReversibleStep() => StepKind.reversible,
  IrreversibleStep() => StepKind.irreversible,
  ObservingStep() => StepKind.observing,
  _ => StepKind.unknown,
};

/// Why a step cannot be taken back, or the empty string when the question does not arise.
///
/// The getter is a step's own code and may throw. One that does is reported rather than allowed to
/// end the reading, because the check consuming this is the one whose job is to notice.
String _reasonOf(Step step, void Function(Finding problem) onFailure) {
  if (step is! IrreversibleStep) {
    return '';
  }
  try {
    return step.irreversibleReason;
  } on Object catch (failure) {
    onFailure(Finding('${step.runtimeType}', 'reading its irreversibleReason threw $failure'));
    return '';
  }
}
