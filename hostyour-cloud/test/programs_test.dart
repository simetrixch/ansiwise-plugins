// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
// A test that could not open `programs/` would be verifying a copy of the program rather than the
// program, which is the one thing this file exists to avoid.
import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// Every program file this deployment ships resolves against the registry.
///
/// This is the check the first gate performs on a machine, run here instead — so a program that
/// names a step nobody registered is caught in the suite rather than on a server.
void main() {
  // The six plugins the shipped configuration turns on, composed the way the binary composes
  // them. Resolved once, because reading a file per test says nothing more than reading it once.
  late final Registry shipped;
  setUpAll(() async => shipped = await shippedRegistry());

  final Directory programs = Directory('$installationRoot/$installationPrograms');

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
        expect(() => ProgramResolver(shipped).resolve(program), returnsNormally);
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
      File(programAt('deploy-host.yaml')).readAsStringSync(),
      where: 'deploy-host.yaml',
    );
    final ResolvedProgram resolved = ProgramResolver(shipped).resolve(program);

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
      (ResolvedStep s) => _built(s) is! ObservingStep,
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

  group('every program asks for the tools it needs, at its head', () {
    // A program that assumes a command is a program that finds out in the middle of itself.
    // deploy-branch would fail at a git identity check with a message about configuration where the
    // truth is a missing git; deploy-gitops at a chart repository where the truth is a missing helm.
    // That the machine usually carries them because an earlier program installed them is a fact of
    // the usual ORDER and not of the program being run.
    //
    // The gate MEASURES and installs nothing, because a program that quietly installed something is
    // a program whose dry run lied: it showed a plan that did not include the installation it was
    // about to perform.

    for (final File file in programs.listSync().whereType<File>().where(
      (File f) => f.path.endsWith('.yaml'),
    )) {
      final String name = file.uri.pathSegments.last;

      ResolvedProgram resolvedProgram() =>
          ProgramResolver(shipped).resolve(loadProgram(file.readAsStringSync(), where: name));

      test('$name gates on its tools before it changes anything', () {
        final ResolvedProgram resolved = resolvedProgram();
        final int gate = resolved.steps.indexWhere(
          (ResolvedStep s) => s.entry.step == const StepName('require_commands'),
        );
        expect(gate, isNot(-1), reason: '$name names no command it needs, so it assumes them all');

        final int firstChange = resolved.steps.indexWhere(
          (ResolvedStep s) => _built(s) is! ObservingStep,
        );
        if (firstChange == -1) {
          return;
        }
        expect(
          gate,
          lessThan(firstChange),
          reason:
              'a gate after the first change fires with the machine already altered, which is the '
              'situation it exists to prevent',
        );
      });

      test('$name asks for no command a step of it never starts', () {
        final ResolvedProgram resolved = resolvedProgram();
        // The FIRST one only. A later `require_commands` is not a gate on what the program assumes:
        // it is the postcondition of an install step, proving that what was installed really landed
        // — deploy-host asks for htpasswd after installing apache2-utils, and no step of it ever
        // starts htpasswd. Judging that one here would demand the program stop proving its own work.
        final int gate = resolved.steps.indexWhere(
          (ResolvedStep s) => s.entry.step == const StepName('require_commands'),
        );
        final Set<String> asked = <String>{
          ..._argumentsOf(resolved.steps[gate]).textList('commands'),
        };
        // Read out of the sources of the steps this program names, so a command that stops being
        // used stops being demanded. A gate asking for a tool nothing needs refuses machines for
        // nothing, and it is the half of this that nobody would otherwise notice.
        final Set<String> started = <String>{
          for (final ResolvedStep step in resolved.steps) ...<String>[
            ..._commandsStartedBy(step.entry.step, step.registered.source),
            ..._clientInvocationOf(step),
          ],
        };
        expect(
          asked.difference(started),
          isEmpty,
          reason:
              '$name demands a command no step of it starts, and a machine refused for a tool '
              'nothing uses is refused for nothing',
        );
      });
    }
  });
}

/// The step [resolved] builds, with the defaults its specification declares.
///
/// The engine fills defaults in before it builds a step, and a reader that skipped that would be
/// refused by any step relying on one — `disable_password_login` takes its drop-in path that way.
Step _built(ResolvedStep resolved) => resolved.registered.create(_argumentsOf(resolved));

/// The arguments [resolved] runs with: what the program wrote, plus what the step declares by
/// default.
Arguments _argumentsOf(ResolvedStep resolved) {
  final Map<String, Object> defaults = <String, Object>{
    for (final ArgumentSpec spec in resolved.registered.arguments)
      if (spec.defaultValue case final Object value) spec.name: value,
  };
  return defaults.isEmpty
      ? resolved.entry.arguments
      : resolved.entry.arguments.withDefaults(defaults);
}

/// The word the cluster client is invoked with, for a step that composes its command line.
///
/// A step that reaches the cluster declares the `kubectl` argument and starts whatever its first
/// word names, so no literal appears in its source for [_commandsStartedBy] to read. The resolved
/// argument — the row's value, or the declared default — is what the run actually starts, and it
/// is read here the same way the engine reads it.
Set<String> _clientInvocationOf(ResolvedStep resolved) {
  final bool composes = resolved.registered.arguments.any(
    (ArgumentSpec spec) => spec.name == 'kubectl',
  );
  if (!composes) {
    return const <String>{};
  }
  final List<String> invocation = _argumentsOf(resolved).textList('kubectl');
  return invocation.isEmpty ? const <String>{} : <String>{invocation.first};
}

/// The commands the step declared at [source] starts, read from its own file.
///
/// `<path>:<line>` is what a registry entry carries, and the path is what is opened here. A step
/// composing a command name out of a variable is not seen, and that is the known limit of reading
/// source: this catches a demand for a tool nothing uses, which is the direction that goes
/// unnoticed, and it does not pretend to enumerate everything a run might start.
Set<String> _commandsStartedBy(StepName step, String source) => <String>{
  for (final RegExpMatch match in _commandName.allMatches(
    _sourceOf(step, source).readAsStringSync(),
  ))
    match.group(1)!,
};

/// The file a registry entry's `<path>:<line>` names, in the plugin that declared [step].
///
/// **A path is relative to the package that declared it, and a program names steps from five.** The
/// plugin is ASKED which names it holds rather than the path being searched for under each of them:
/// two packages already carry a `lib/src/steps/template.dart`, so a search would have to choose
/// between two real files, and choosing wrong reads a different step's source without saying so.
///
/// **A step no active plugin claims FAILS, and so does a path that is not there.** Answering with no
/// commands would make every tool the gate demands look unused, and the test would report the
/// opposite of the truth while staying green.
File _sourceOf(StepName step, String source) {
  final String path = source.split(':').first;
  final List<String> claiming = <String>[
    for (final Plugin plugin in compiledPlugins.available)
      if (plugin.registry.steps.containsKey(step)) plugin.name,
  ];
  if (claiming.length != 1) {
    throw StateError(
      claiming.isEmpty
          ? '$step is in the program and in no plugin of ${compiledPlugins.names.join(', ')}'
          : '$step is registered by ${claiming.join(' and ')}, so its source is ambiguous',
    );
  }
  final File file = File('../${claiming.single}/$path');
  if (!file.existsSync()) {
    throw StateError(
      '${claiming.single} registers $step at $path, and that file is not there — the entry points at '
      'something that was moved or deleted',
    );
  }
  return file;
}

final RegExp _commandName = RegExp(r"Command(?:\.observing)?\(\s*'([a-z0-9_.-]+)'");
