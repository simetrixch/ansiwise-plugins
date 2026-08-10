import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';

Future<void> main() async {
  const ConfigValidity check = ConfigValidity(files: RealFiles(), registry: executionRegistry);
  final List<String> onDisk = await check.programFiles();
  final ProgramReading reading = await check.read();

  test('$programsDirectory holds program files to judge', () {
    expect(
      onDisk,
      isNotEmpty,
      reason: 'a check that read no program file would pass over a tree it never opened',
    );
  });

  test('every program file on disk was read', () {
    // The files are counted here and the outcomes there, and the two have to agree. A reading that
    // walked the directory and found nothing would otherwise report no refusal and be taken for
    // agreement.
    expect(
      reading.outcomes.map((ProgramOutcome outcome) => outcome.file),
      unorderedEquals(onDisk),
      reason: 'some file in $programsDirectory was never read',
    );
  });

  test('every program file loads and binds to the registry', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          'no unknown step, no unknown predicate, no undeclared argument, no missing required '
          'argument and no value of the wrong kind — this is what an operator would meet on the '
          'machine at the moment they least want to read a refusal',
    );
  });

  test('the steps of those files are bound to real registry entries', () {
    expect(
      reading.stepCount,
      greaterThan(0),
      reason: 'every program resolved to nothing, so the binding was never exercised',
    );
  });

  group('counter-probe', () {
    // Three programs written here and run through the same resolver. Two must be refused and one must
    // be accepted: a resolver that accepted everything would pass a tree whose programs are all
    // broken, and one that refused everything would be caught only by the third — which is why the
    // accepted one is generated FROM the registry rather than typed out. It carries whatever the
    // first registered step declares, so it stays a true program on the day that step gains an
    // argument.

    const ProgramResolver resolver = ProgramResolver(executionRegistry);

    test('the registry holds a step a program could name', () {
      expect(
        executionRegistry.steps,
        isNotEmpty,
        reason: 'a program can name nothing, so nothing below was measured',
      );
    });

    test('a step no registry holds is refused', () {
      expect(
        resolve(resolver, _namesAnUnknownStep, 'planted-unknown-step.yaml'),
        isA<ProgramRefused>(),
      );
    });

    test('a program built from the registry resolves', () {
      expect(
        resolve(resolver, _validProgramText, 'planted-program.yaml'),
        isA<ProgramResolved>(),
        reason: 'this resolver refuses everything, so the refusals above prove nothing',
      );
    });

    test('an argument no step declares is refused', () {
      expect(
        resolve(
          resolver,
          '$_validProgramText    no_step_declares_this_argument: 1\n',
          'planted-extra-argument.yaml',
        ),
        isA<ProgramRefused>(),
      );
    });

    test('a refusal names every problem it found, one line each', () {
      final ProgramOutcome outcome = resolve(
        resolver,
        _namesAnUnknownStep,
        'planted-unknown-step.yaml',
      );
      expect(
        (outcome as ProgramRefused).problems,
        isNotEmpty,
        reason: 'a refusal with no lines in it tells the person fixing the file nothing',
      );
    });
  });
}

const String _namesAnUnknownStep = '''
name: planted-unknown-step
roles: [master]
steps:
  - step: no_step_is_registered_under_this_name
    on_failure: exit
''';

/// A program file naming the registry's own first step, with a value for every argument it declares.
final String _validProgramText = _programTextFor(executionRegistry.steps.values.first);

String _programTextFor(RegisteredStep entry) {
  final Arguments given = plausibleArguments(entry.arguments);
  final StringBuffer text = StringBuffer()
    ..writeln('name: planted-program')
    ..writeln('roles: [master]')
    ..writeln('steps:')
    ..writeln('  - step: ${entry.name.value}')
    ..writeln('    on_failure: exit');
  for (final ArgumentSpec spec in entry.arguments) {
    text.writeln('    ${spec.name}: ${_asYaml(given.raw(spec.name))}');
  }
  return text.toString();
}

/// [value] written the way a program file writes it.
///
/// Text is always quoted, so a value that YAML would read as a number, as a date or as true stays the
/// text the step declared. The quote inside is doubled, which is how a single-quoted YAML scalar
/// carries one.
String _asYaml(Object? value) => switch (value) {
  final String text => "'${text.replaceAll("'", "''")}'",
  final List<String> texts => '[${texts.map(_asYaml).join(', ')}]',
  null => 'null',
  _ => '$value',
};
