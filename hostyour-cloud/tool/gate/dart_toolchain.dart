/// The Dart toolchain, as the gate asks it things.
///
/// A check that started `dart` itself could not be run without `dart` on the path, which is how a
/// check becomes something people skip, and it could not be shown to read the tool's answer
/// correctly either — the only way to prove that is to hand it an answer and see what it decides.
/// So the toolchain is a port with a real implementation and a fake beside it, the same shape the
/// framework gives `Shell`, `Files`, `Http` and `Clock`.
///
/// Two kinds of call, and the difference is real rather than stylistic. What the gate READS it
/// captures, because it has to parse what came back. What the gate SHOWS goes straight to this
/// process's output, because a person is watching a test suite run and a captured suite appears all
/// at once when it is over.
library;

/// What a captured run of the toolchain answered.
final class ToolRun {
  /// Records an exit code and everything the tool wrote.
  const ToolRun({required this.exitCode, required this.output});

  /// What the tool exited with.
  ///
  /// Not read as a verdict on its own: `dart analyze` answers 1, 2 and 3 for different severities and
  /// 0 for a run that found nothing, so what a check reports is the issues themselves.
  final int exitCode;

  /// Standard output and standard error together, in that order.
  final String output;

  /// Whether the tool exited cleanly.
  bool get succeeded => exitCode == 0;
}

/// What the gate does with the `dart` executable.
abstract interface class DartToolchain {
  /// Resolves the dependencies of the package in [directory].
  ///
  /// Nothing below can say anything true without a resolved package config: the analyzer reports
  /// every import as unresolved and the failure reads as a tree full of defects.
  Future<ToolRun> pubGet({required String directory});

  /// Asks the analyzer about the package in [directory], with every info fatal.
  Future<ToolRun> analyze({required String directory});

  /// Asks the formatter what it would change under [directory], writing nothing.
  ///
  /// A check that repaired what it measures would be green the second time for having changed the
  /// thing it judged.
  Future<ToolRun> format({required String directory});

  /// Runs the test suite of the package in [directory], showing it as it goes.
  Future<int> runTests({required String directory});

  /// Runs [script] of the package in [directory], showing it as it goes.
  Future<int> runScript(String script, {required String directory});

  /// Compiles [entryPoint] of the package in [directory] into a self-contained executable at
  /// [target].
  Future<ToolRun> compileExecutable({
    required String directory,
    required String entryPoint,
    required String target,
  });

  /// What the toolchain calls itself, for the line a build prints.
  Future<ToolRun> version({required String directory});
}
