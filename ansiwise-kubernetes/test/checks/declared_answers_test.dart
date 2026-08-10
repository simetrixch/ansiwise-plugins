import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

/// declared-answers — the probe plants what an installation plants.
///
/// A step reads an answer BY NAME, and the KIND and the DEFAULT of that value are declared by the
/// program file of the product that runs the step — never by the step and never by this package,
/// which ships no program file at all. A probe that invents a value therefore exercises a branch no
/// installation takes, while the branch every installation DOES take is measured by nothing and the
/// step is counted as covered.
///
/// That is not hypothetical: every answer used to be handed the text `x`, and a step whose answer is
/// declared `default: ''` was reported as exercised on a value the product never gives it.
///
/// So the declarations are read out of the installation's own programs, and what no program declares
/// is NAMED rather than quietly replaced by a placeholder.
Future<void> main() async {
  final List<ArgumentSpec> declared = await answerSpecsIn(
    const RealFiles(),
    installationProgramsRoot,
  );
  final PlantedAnswers planted = await answersDeclaredBy(kubernetesRegistry);
  final Set<String> read = <String>{
    for (final RegisteredStep entry in kubernetesRegistry.steps.values) ...entry.answers,
  };

  test('the programs declare answers to read', () {
    expect(
      declared,
      isNotEmpty,
      reason:
          'no answer declaration was read out of $installationProgramsRoot, so every value below '
          'is a guess wearing the shape of a reading',
    );
  });

  test('${read.length} answer(s) are read by this package, and the probe plants exactly those', () {
    expect(
      planted.values.names.toSet(),
      read,
      reason:
          'a value planted for a name no step reads is planted for nobody, and a name a step reads '
          'with no value planted for it makes the step throw where nothing about it is measured',
    );
  });

  test('every answer this package reads is declared by a program', () {
    expect(
      planted.notDeclared,
      isEmpty,
      reason:
          'a probe can only guess at an answer no program declares, and a guessed value is exactly '
          'what this check exists to end; either the installation is missing the declaration, or '
          'the step reaches for a name nothing gives it',
    );
  });

  test('an answer the programs give a default is planted with that default', () {
    final List<ArgumentSpec> withDefaults = <ArgumentSpec>[
      for (final ArgumentSpec spec in declared)
        if (spec.hasDefault && read.contains(spec.name)) spec,
    ];
    expect(
      withDefaults,
      isNotEmpty,
      reason:
          'not one answer this package reads is declared with a default, so this assertion holds '
          'nothing against anything',
    );
    for (final ArgumentSpec spec in withDefaults) {
      expect(
        planted.values.raw(spec.name),
        spec.defaultValue,
        reason:
            '${spec.name} is declared with a default and was planted with something else, so the '
            'branch a program that says nothing about it takes is measured by nothing',
      );
    }
  });

  group('counter-probe', () {
    // The planting is driven over declarations written here, so each rule is shown to hold and the
    // one that would hide a defect — silently substituting a placeholder — is shown to report.

    const ArgumentSpec empty = ArgumentSpec(
      name: 'planted_empty',
      kind: ArgumentKind.text,
      describes: 'a planted answer whose declaration gives it an empty default',
      required: false,
      defaultValue: '',
    );
    const ArgumentSpec chosen = ArgumentSpec(
      name: 'planted_chosen',
      kind: ArgumentKind.text,
      describes: 'a planted answer that may hold one of two words',
      allowed: <String>['first', 'second'],
    );
    const ArgumentSpec plain = ArgumentSpec(
      name: 'planted_plain',
      kind: ArgumentKind.text,
      describes: 'a planted answer with neither a default nor a closed set',
    );

    test('a declared default is what the probe plants, not a placeholder', () {
      expect(
        answersFrom(<String>{empty.name}, <ArgumentSpec>[empty]).values.raw(empty.name),
        '',
        reason:
            'this is the defect that put a step in the covered column while the branch a real run '
            'takes was never entered',
      );
    });

    test('a closed set of values is planted with one of them', () {
      expect(
        answersFrom(<String>{chosen.name}, <ArgumentSpec>[chosen]).values.raw(chosen.name),
        'first',
        reason: 'a step that decides on such a value refuses anything outside the set, correctly',
      );
    });

    test('an answer no program declares is reported rather than guessed at in silence', () {
      final PlantedAnswers found = answersFrom(<String>{'planted_unknown'}, const <ArgumentSpec>[]);
      expect(found.notDeclared, <String>['planted_unknown']);
      expect(
        found.values.raw('planted_unknown'),
        plausibleText,
        reason: 'the step is still built, or nothing at all would be measured about it',
      );
    });

    test('an answer that is declared is not reported as undeclared', () {
      expect(
        answersFrom(<String>{plain.name}, <ArgumentSpec>[plain]).notDeclared,
        isEmpty,
        reason: 'a probe that reported every name would pass the test above having read nothing',
      );
    });

    test('a declaration nothing reads plants no value', () {
      expect(
        answersFrom(const <String>{}, <ArgumentSpec>[empty]).values.names,
        isEmpty,
        reason: 'an answer no step of this registry reads is a value planted for nobody',
      );
    });
  });
}
