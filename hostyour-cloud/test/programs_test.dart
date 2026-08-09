// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
// A test that could not open `programs/` would be verifying a copy of the program rather than the
// program, which is the one thing this file exists to avoid.
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

/// Every program file this deployment ships resolves against the registry.
///
/// This is the check the first gate performs on a machine, run here instead — so a program that
/// names a step nobody registered is caught in the suite rather than on a server.
void main() {
  final Directory programs = Directory('programs');

  test('there is at least one program to check', () {
    expect(programs.existsSync(), isTrue, reason: 'run this from the deployment package');
    expect(programs.listSync().whereType<File>(), isNotEmpty);
  });

  for (final File file in programs.listSync().whereType<File>().where(
    (File f) => f.path.endsWith('.yaml'),
  )) {
    final String name = file.uri.pathSegments.last;

    group(name, () {
      test('loads', () {
        expect(() => loadProgram(file.readAsStringSync(), where: name), returnsNormally);
      });

      test('every step and predicate it names is registered, and every argument fits', () {
        final Program program = loadProgram(file.readAsStringSync(), where: name);
        expect(() => const ProgramResolver(executionRegistry).resolve(program), returnsNormally);
      });

      test('every step declares what a failure costs', () {
        final Program program = loadProgram(file.readAsStringSync(), where: name);
        // The loader already refuses a missing policy. This asserts the property from the other
        // side, so that removing that refusal is caught here rather than on a machine.
        expect(program.steps, isNotEmpty);
        for (final ProgramStep step in program.steps) {
          expect(
            OnFailure.values,
            contains(step.onFailure),
            reason: '${step.step} has no failure policy',
          );
        }
      });
    });
  }

  test('deploy-host measures the machine before it changes anything', () {
    final Program program = loadProgram(
      File('programs/deploy-host.yaml').readAsStringSync(),
      where: 'deploy-host.yaml',
    );
    final ResolvedProgram resolved = const ProgramResolver(executionRegistry).resolve(program);

    // The ordering the whole preflight exists for: a machine that was never going to work is
    // refused before anything is written to it.
    //
    // The rule is about the gates that measure the machine AS FOUND. A gate that comes after a
    // change is a different thing — it is that change's proof, and it is what makes a verdict come
    // from a postcondition rather than from an exit code. `require_commands` proves
    // `install_packages`; `require_key_login_possible` proves `install_authorized_key`.
    const List<StepName> preflight = <StepName>[
      StepName('require_pinned_ubuntu'),
      StepName('require_machine_size'),
      StepName('require_free_disk'),
    ];

    final int firstChange = resolved.steps.indexWhere(
      (ResolvedStep s) => s.registered.create(s.entry.arguments) is! ObservingStep,
    );
    expect(firstChange, isNot(-1), reason: 'this program changes nothing at all');

    for (final StepName gate in preflight) {
      final int at = resolved.steps.indexWhere((ResolvedStep s) => s.entry.step == gate);
      expect(at, isNot(-1), reason: '$gate is not in this program');
      expect(
        at,
        lessThan(firstChange),
        reason: '$gate measures the machine as found and must come before anything changes it',
      );
    }
  });
}
