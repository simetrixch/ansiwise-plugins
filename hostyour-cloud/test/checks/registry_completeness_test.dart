import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

void main() {
  final SourceTree tree = SourceTree.on(repositoryRoot());
  final RegistryReading reading = RegistryReading.of(executionRegistry);
  final RegistryCompleteness check = RegistryCompleteness(tree: tree, reading: reading);

  test('the registry holds entries to count', () {
    // A registry read as empty would pass every assertion below without making one.
    expect(
      reading.entries,
      isNotEmpty,
      reason: 'no registry entry was read at all, so nothing below was measured',
    );
  });

  test('there are step classes on disk to count against', () {
    expect(
      check.classesOnDisk,
      isNotEmpty,
      reason:
          'no step class was found under $stepsDirectory, so the unregistered half was not measured',
    );
  });

  test('the class an entry builds is read off the object', () {
    // The one thing that cannot be checked against the tree. Under a build that gives class names
    // away, PlantedStep comes back as something else and this says so, instead of every entry in the
    // registry quietly failing to match its own file.
    expect(
      RegistryReading.of(_registryOf(_plantedEntry)).entries.single.className,
      'PlantedStep',
      reason: 'a step registered here builds PlantedStep, and this read something else',
    );
  });

  test('every entry names a real file and line that declares the class it builds', () {
    expect(
      check.findings,
      isEmpty,
      reason:
          'the source of an entry is what an operator opens when a step fails, and nothing but this '
          'check keeps it true',
    );
  });

  group('counter-probe', () {
    // Both halves of the source verification, over a file this check writes: the right line must be
    // accepted and three near misses must not. A test that only proved the accepting direction would
    // pass just as well if the function answered yes to everything, which is the shape a check rots
    // into.

    final SourceTree planted = SourceTree.planted(<String, String>{
      'pubspec.yaml': 'name: planted_package\n',
      'lib/src/steps/host/planted.dart': _plantedDeclarations,
    });
    const String plantedPath = 'lib/src/steps/host/planted.dart';

    test('the planted declaration on line 4 is recognised', () {
      expect(
        declaresClass(planted, path: plantedPath, line: 4, className: 'PlantedStep'),
        isTrue,
        reason: 'this check cannot verify a source line at all',
      );
    });

    test('line 3 only names the class in a comment and is not its declaration', () {
      expect(declaresClass(planted, path: plantedPath, line: 3, className: 'PlantedStep'), isFalse);
    });

    test('line 5 is not the declaration, so a drifted line number does not pass', () {
      expect(declaresClass(planted, path: plantedPath, line: 5, className: 'PlantedStep'), isFalse);
    });

    test('the class name on the line is read, not just the shape of the line', () {
      expect(
        declaresClass(planted, path: plantedPath, line: 4, className: 'PlantedHelper'),
        isFalse,
      );
    });

    for (final String bad in <String>[
      '/etc/passwd',
      'C:/tree/file.dart',
      '../outside/file.dart',
      'lib/../../file.dart',
    ]) {
      test('"$bad" is not accepted as a repository-relative path', () {
        expect(sourceIsRepositoryRelative(bad), isFalse);
      });
    }

    test('an ordinary repository-relative path is accepted', () {
      expect(
        sourceIsRepositoryRelative('lib/src/steps/host/planted.dart'),
        isTrue,
        reason: 'every entry in the real registry would otherwise be reported',
      );
    });

    for (final String shape in <String>[
      'PlantedStep',
      'PlantedGeneric',
      'PlantedNested',
      'PlantedWithMixin',
      'PlantedWrapped',
    ]) {
      test('$shape is found on disk', () {
        expect(
          stepClassesIn(planted, under: stepsDirectory).map((DeclaredStepClass c) => c.className),
          contains(shape),
          reason:
              'a step class this scan cannot see is a step nothing reports as unregistered, and '
              'the unregistered half of this check is then green for having looked past it',
        );
      });
    }

    for (final String allowed in <String>[
      'PlantedBase',
      'PlantedGenericBase',
      '_PlantedPrivate',
      'PlantedHelper',
    ]) {
      test('$allowed is not a registrable step and is not reported as one', () {
        expect(
          stepClassesIn(planted, under: stepsDirectory).map((DeclaredStepClass c) => c.className),
          isNot(contains(allowed)),
        );
      });
    }

    test('a step class with no entry is reported', () {
      final RegistryCompleteness onPlanted = RegistryCompleteness(
        tree: planted,
        reading: RegistryReading.of(_emptyRegistry),
      );
      expect(
        about(onPlanted.findings, plantedPath),
        isNotEmpty,
        reason: 'an unregistered step class is a class no program file can ever name',
      );
    });

    test('an entry whose source points at the wrong line is reported', () {
      final RegistryCompleteness drifted = RegistryCompleteness(
        tree: planted,
        reading: RegistryReading.of(_registryOf(_entryAt('$plantedPath:5'))),
      );
      expect(
        about(drifted.findings, 'planted'),
        isNotEmpty,
        reason: 'a source line that drifted by one is exactly what this check exists to catch',
      );
    });

    test('a predicate whose source points at the wrong line is reported', () {
      final RegistryCompleteness drifted = RegistryCompleteness(
        tree: SourceTree.planted(<String, String>{
          'pubspec.yaml': 'name: planted_package\n',
          'lib/src/steps/gitops/stage_toggle.dart': _plantedPredicateDeclaration,
        }),
        reading: RegistryReading.of(
          _registryOfPredicate('lib/src/steps/gitops/stage_toggle.dart:1'),
        ),
      );
      expect(
        about(drifted.findings, 'planted_predicate'),
        isNotEmpty,
        reason:
            "a predicate's source rots exactly the way a step's does, and it is what the plan sends "
            'an operator to',
      );
    });

    test('a predicate pointing at its declaration is left alone', () {
      final RegistryCompleteness onTarget = RegistryCompleteness(
        tree: SourceTree.planted(<String, String>{
          'pubspec.yaml': 'name: planted_package\n',
          'lib/src/steps/gitops/stage_toggle.dart': _plantedPredicateDeclaration,
        }),
        reading: RegistryReading.of(
          _registryOfPredicate('lib/src/steps/gitops/stage_toggle.dart:2'),
        ),
      );
      expect(
        about(onTarget.findings, 'planted_predicate'),
        isEmpty,
        reason: 'a predicate is declared with implements, not extends, and both must be read',
      );
    });

    test('a predicate that describes nothing is reported', () {
      final RegistryCompleteness silent = RegistryCompleteness(
        tree: SourceTree.planted(<String, String>{
          'pubspec.yaml': 'name: planted_package\n',
          'lib/src/steps/gitops/stage_toggle.dart': _plantedPredicateDeclaration,
        }),
        reading: RegistryReading.of(
          _registryOfPredicate('lib/src/steps/gitops/stage_toggle.dart:2', describes: '  '),
        ),
      );
      expect(
        about(silent.findings, 'planted_predicate'),
        isNotEmpty,
        reason: 'what a predicate describes is the line the operator reads in the plan',
      );
    });

    test('the same entry pointing at the declaration is left alone', () {
      final RegistryCompleteness onTarget = RegistryCompleteness(
        tree: planted,
        reading: RegistryReading.of(_registryOf(_entryAt('$plantedPath:4'))),
      );
      expect(
        about(onTarget.findings, 'planted'),
        isEmpty,
        reason:
            'this check reports every entry, so its silence about the real registry means '
            'nothing',
      );
    });
  });
}

/// A registry holding [entry] and nothing else.
Registry _registryOf(RegisteredStep entry) => Registry(
  steps: <StepName, RegisteredStep>{entry.name: entry},
  predicates: const <PredicateName, RegisteredPredicate>{},
);

/// A registry holding nothing, so a step class on disk has nothing to match against.
const Registry _emptyRegistry = Registry(
  steps: <StepName, RegisteredStep>{},
  predicates: <PredicateName, RegisteredPredicate>{},
);

/// An entry for [PlantedStep] claiming to be declared at [source].
RegisteredStep _entryAt(String source) =>
    RegisteredStep(name: const StepName('planted'), source: source, create: _plant);

/// A registry holding one predicate, claiming to be declared at [source].
Registry _registryOfPredicate(
  String source, {
  String describes = 'whether the planted flag is on',
}) => Registry(
  steps: const <StepName, RegisteredStep>{},
  predicates: <PredicateName, RegisteredPredicate>{
    const PredicateName('planted_predicate'): RegisteredPredicate(
      name: const PredicateName('planted_predicate'),
      source: source,
      predicate: const PlantedPredicate(),
      describes: describes,
    ),
  },
);

/// The declaration the planted predicate's source has to point at.
///
/// Line 2 is the declaration; line 1 is a doc comment naming the class as prose. Written as a list of
/// lines for the same reason as [_plantedDeclarations].
final String _plantedPredicateDeclaration = <String>[
  '/// A PlantedPredicate, named here as prose rather than declared.',
  'final class PlantedPredicate implements Predicate {',
  '}',
].join('\n');

final RegisteredStep _plantedEntry = _entryAt('test/checks/registry_completeness_test.dart:1');

Step _plant(Arguments arguments) => const PlantedStep();

/// A file planted so the scans above can be shown to work.
///
/// Line 3 names PlantedStep as prose and is not a declaration; line 4 is the declaration. The three
/// classes below it are each excluded for a different reason — abstract, private, and not a step —
/// and each is written WITHOUT a closing brace on its line, so it is the rule under test that
/// excludes it rather than the line merely failing to look like a declaration.
///
/// Written as a list of lines rather than as one multi-line string, because this file is itself
/// scanned by the reversibility check next door: a line reading `class X extends Step` at column
/// zero would be a declaration as far as that scan is concerned, and this test would turn the tree
/// red for a class that does not exist.
final String _plantedDeclarations = <String>[
  '/// A step planted here so this check can prove it reads a declaration.',
  '///',
  '/// The name PlantedStep appears on this line as prose, and this line is not a declaration.',
  'final class PlantedStep extends ReversibleStep {',
  '  const PlantedStep();',
  '}',
  '',
  // The four shapes a real step wears, and the reason this fixture lists them. It used to plant
  // only the line above — the one form with nothing after the kind — and stayed green while
  // forty-seven of the plugin's ninety-one step classes became invisible to the scan. A probe that
  // plants yesterday's shape proves the check works on yesterday's code.
  'final class PlantedGeneric extends ReversibleStep<bool> {',
  '}',
  '',
  'final class PlantedNested extends ReversibleStep<List<String>> {',
  '}',
  '',
  'final class PlantedWithMixin extends ReversibleStep<String?> with FileStep {',
  '}',
  '',
  // What dart format does once the name and its type argument no longer fit in one line.
  'final class PlantedWrapped',
  '    extends ReversibleStep<({String? args, bool binding})> {',
  '}',
  '',
  'abstract base class PlantedBase extends Step {',
  '}',
  '',
  'abstract base class PlantedGenericBase extends ReversibleStep<String?> {',
  '}',
  '',
  'final class _PlantedPrivate extends ObservingStep {',
  '}',
  '',
  'final class PlantedHelper {',
  '}',
].join('\n');

/// A predicate that exists only so an entry above can register one.
final class PlantedPredicate implements Predicate {
  const PlantedPredicate();

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async =>
      const PredicateResult.holds('nothing is asked of this predicate');
}

/// A step that exists only so an entry above can build one.
final class PlantedStep extends ObservingStep {
  const PlantedStep();

  @override
  Future<CheckResult> check(StepContext context) async =>
      const CheckResult.satisfied('nothing is asked of this step');
}
