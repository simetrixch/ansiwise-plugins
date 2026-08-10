import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_host/ansiwise_host.dart';
import 'package:test/test.dart';

void main() {
  final RegistryReading reading = RegistryReading.of(hostRegistry);
  final Reversibility check = Reversibility(
    tree: SourceTree.on(repositoryRoot()),
    reading: reading,
  );

  test('the registry holds entries whose kind can be read', () {
    expect(
      reading.entries,
      isNotEmpty,
      reason: "no registry entry was read at all, so no step's kind was measured",
    );
  });

  test('every registered step is reversible, irreversible or observing', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'a step that answers neither leaves a dry run unable to say whether it has passed the '
          'point of no return, and an irreversible one has to say what is lost',
    );
  });

  group('counter-probe', () {
    // The placeholder judgement, from both sides. Only the second half has teeth in a tree whose
    // reasons are all good: a rule that called everything a placeholder would turn every irreversible
    // step red, and a rule that called nothing one is the state this check would rot into.

    for (final String planted in <String>[
      'todo',
      'TODO',
      'n/a',
      'none',
      'not implemented',
      'No undo implemented',
      'undo not implemented',
      'cannot be undone.',
      'irreversible',
      '   ',
    ]) {
      test('"$planted" is not accepted as a reason', () {
        expect(
          reasonIsAPlaceholder(planted),
          isTrue,
          reason: 'a step that says nothing about what is lost would pass',
        );
      });
    }

    for (final String planted in <String>[
      'the packages are gone and nothing recorded which of them this removed, so putting them back '
          'would mean guessing',
      'the archives are deleted, and nothing recorded which of them were there to fetch again',
      'the binary that was on this machine is overwritten, and what is lost is the version nothing '
          'wrote down',
    ]) {
      test('a reason that says what is lost is left alone', () {
        expect(
          reasonIsAPlaceholder(planted),
          isFalse,
          reason: 'this check refuses a real reason, so every irreversible step would be red',
        );
      });
    }

    // The direct-extension scan, over a tree this test plants: the violation must be reported and
    // the three kinds must not, or the scan would turn the framework's own step.dart red.
    final SourceTree planted = SourceTree.planted(<String, String>{
      'pubspec.yaml': 'name: planted_package\n',
      'lib/src/domain/step.dart': _plantedKinds,
    });
    final Iterable<String> reported = classesExtendingStepItself(
      planted,
    ).map((DeclaredStepClass declared) => declared.className);

    test('a planted class extending Step itself is reported', () {
      expect(reported, contains('PlantedDirect'), reason: 'this scan cannot go red');
    });

    for (final String allowed in <String>[...theThreeKinds, 'PlantedProper']) {
      test('$allowed is not reported', () {
        expect(
          reported,
          isNot(contains(allowed)),
          reason: 'this scan refuses the very shape every step has',
        );
      });
    }

    test('an irreversible step whose reason says nothing is reported', () {
      final Reversibility onPlanted = Reversibility(
        tree: planted,
        reading: RegistryReading.of(_registryOf(const _SaysNothingIsLost())),
      );
      expect(
        about(onPlanted.findings, 'planted'),
        isNotEmpty,
        reason: 'a placeholder compiles and reads like an answer, which is why it needs a check',
      );
    });

    test('an irreversible step that says what is lost is left alone', () {
      final Reversibility onPlanted = Reversibility(
        tree: planted,
        reading: RegistryReading.of(_registryOf(const _SaysWhatIsLost())),
      );
      expect(
        about(onPlanted.findings, 'planted'),
        isEmpty,
        reason: 'this check reports every irreversible step, so its silence means nothing',
      );
    });
  });
}

/// The three kinds and two planted classes, as the lines of one file.
///
/// Written as a list of lines rather than as one multi-line string, because this file is itself
/// scanned by the check it holds: a line reading `class X extends Step` at column zero would be a
/// declaration as far as that scan is concerned, and this test would turn the tree red.
final String _plantedKinds = <String>[
  'abstract base class ReversibleStep extends Step {',
  'abstract base class IrreversibleStep extends Step {',
  'abstract base class ObservingStep extends Step {',
  'final class PlantedDirect extends Step {',
  'final class PlantedProper extends ObservingStep {',
].join('\n');

/// A registry holding [step] under the name `planted` and nothing else.
Registry _registryOf(Step step) => Registry(
  steps: <StepName, RegisteredStep>{
    const StepName('planted'): RegisteredStep(
      name: const StepName('planted'),
      source: 'lib/src/steps/host/planted.dart:1',
      create: (Arguments arguments) => step,
    ),
  },
  predicates: const <PredicateName, RegisteredPredicate>{},
);

/// A step that cannot be taken back and says so with a word instead of a reason.
final class _SaysNothingIsLost extends IrreversibleStep {
  const _SaysNothingIsLost();

  @override
  String get irreversibleReason => 'not implemented';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing to do');

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step that cannot be taken back and says what an operator loses by going on.
final class _SaysWhatIsLost extends IrreversibleStep {
  const _SaysWhatIsLost();

  @override
  String get irreversibleReason =>
      'the packages this removed are gone, and nothing recorded which of them were there to fetch '
      'again';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.nothing('nothing to do');

  @override
  Future<void> apply(StepContext context) async {}
}
