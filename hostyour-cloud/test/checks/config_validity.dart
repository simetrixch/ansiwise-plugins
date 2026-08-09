/// config-validity — every program file loads and resolves.
///
/// A program file is data: it names steps, gives them values, and says what a failure of each costs
/// the run. Nothing about that is checked when the code is compiled, which is the whole reason the
/// framework has a loader that refuses what it does not recognise and a resolver that finds every
/// name in the registry. An unknown step, an unknown predicate, an argument no step declares, a
/// required argument nobody gave, a value of the wrong kind — each is refused before the first thing
/// is looked at, let alone changed.
///
/// THIS IS THE FIRST HALF OF WHAT `--mode test` DOES, run here so that a program that does not add up
/// is caught in the tree rather than on a machine. It is the same code both times — `loadProgram` and
/// `ProgramResolver` are called rather than reimplemented — so this can never come to disagree with
/// what an operator's run would do.
///
/// The refusals are reported one line each, because that is how the loader writes them: everything
/// wrong with a file at once, in the order the file reads, so a person fixing one runs it once.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

import 'finding.dart';

/// What the loader and the resolver said about one program file.
sealed class ProgramOutcome {
  const ProgramOutcome(this.file);

  /// The file name, as it sits in the programs directory.
  final String file;
}

/// A file that loaded and bound every name it writes to the registry.
final class ProgramResolved extends ProgramOutcome {
  /// Records that [file] resolved to [steps] steps.
  const ProgramResolved(super.file, this.steps);

  /// How many steps it holds.
  final int steps;

  @override
  String toString() => '$file resolved to $steps step(s)';
}

/// A file the loader or the resolver refused, with every problem it named.
final class ProgramRefused extends ProgramOutcome {
  /// Records that [file] was refused for [problems].
  const ProgramRefused(super.file, this.problems);

  /// One line per problem, in the order the file reads.
  final List<String> problems;

  @override
  String toString() => '$file was refused: ${problems.join('; ')}';
}

/// Every program file of a directory, loaded and bound to a registry.
final class ProgramReading {
  /// Records what each file turned out to be.
  const ProgramReading(this.outcomes);

  /// One outcome per file, sorted by file name.
  final List<ProgramOutcome> outcomes;

  /// Every refusal, one finding per line of it.
  List<Finding> get findings => <Finding>[
    for (final ProgramRefused refused in outcomes.whereType<ProgramRefused>())
      for (final String problem in refused.problems) Finding(refused.file, problem),
  ];

  /// How many files bound cleanly.
  int get resolvedCount => outcomes.whereType<ProgramResolved>().length;

  /// How many steps those files name in total.
  int get stepCount => outcomes.whereType<ProgramResolved>().fold(
    0,
    (int total, ProgramResolved resolved) => total + resolved.steps,
  );
}

/// The check itself, over a directory and a registry it is given.
final class ConfigValidity {
  /// Reads [directory] through [files] and binds every name to [registry].
  const ConfigValidity({
    required this.files,
    required this.registry,
    this.directory = programsDirectory,
  });

  /// How the program files are read — the framework's own port, so nothing here opens a file itself.
  final Files files;

  /// What every name in a program file has to be found in.
  final Registry registry;

  /// Where the program files live, relative to the repository root.
  final String directory;

  /// The program files in [directory], sorted.
  ///
  /// The port lists names rather than paths, which is what `LoadedCatalogue` does with the same
  /// listing.
  Future<List<String>> programFiles() async {
    final List<String> names = <String>[
      for (final String name in await files.list(directory))
        if (name.endsWith('.yaml')) name,
    ];
    return names..sort();
  }

  /// What the loader and the resolver say about each file.
  Future<ProgramReading> read() async {
    final ProgramResolver resolver = ProgramResolver(registry);
    final List<ProgramOutcome> outcomes = <ProgramOutcome>[];
    for (final String name in await programFiles()) {
      outcomes.add(resolve(resolver, await files.read('$directory/$name'), name));
    }
    return ProgramReading(outcomes);
  }
}

/// Where the program files live, relative to the repository root.
const String programsDirectory = 'programs';

/// What [resolver] makes of the program in [text], filed under [name].
ProgramOutcome resolve(ProgramResolver resolver, String text, String name) {
  try {
    return ProgramResolved(name, resolver.resolve(loadProgram(text, where: name)).steps.length);
  } on ProgramInvalid catch (refused) {
    return ProgramRefused(name, refused.message.split('\n'));
  }
}
