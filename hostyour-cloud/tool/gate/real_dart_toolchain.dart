/// The `dart` this program is itself running under.
library;

import 'dart:io';

import 'dart_toolchain.dart';

/// Starts the real `dart`, in the directory the package sits in.
///
/// [Platform.resolvedExecutable] rather than the word `dart` on the PATH, and that is the whole
/// point of naming it here: the tool that judges the code is then the same one that compiled the
/// judge, so a machine carrying two SDKs cannot analyse the tree with one and report under the name
/// of the other. It is also what makes the version guard sufficient: the guard reads this process's
/// own version, and this is the line that makes that version the one every step runs on.
///
/// Every call runs FROM inside the package rather than naming it as an argument, so the
/// analysis_options that applies is the one that package ships.
final class RealDartToolchain implements DartToolchain {
  /// Creates the real toolchain.
  const RealDartToolchain();

  @override
  Future<ToolRun> pubGet({required String directory}) =>
      _capture(<String>['pub', 'get'], directory: directory);

  /// How the analyzer is started, and why the flags are a value rather than a literal.
  ///
  /// `--fatal-infos` is not a preference. This repository's analysis options turn on strict casts,
  /// strict inference and strict raw types, and every one of them reports at INFO — so a run without
  /// the flag reports success over exactly the fault class those settings exist to catch. Dropping
  /// it leaves every test green and the gate blind, because nothing is wrong with the OUTPUT for a
  /// parser to notice; the invocation is what changed.
  ///
  /// Named so a check can drive it. test/checks/analysis_check_test.dart judges one planted tree
  /// twice — with the flag and without — because "it went red" proves nothing until the weakened
  /// invocation is shown to go green on the very same tree.
  static const List<String> analyzerArgv = <String>['analyze', '--fatal-infos', '--fatal-warnings'];

  /// How the formatter is started.
  ///
  /// `--output=none` so a red run leaves the tree exactly as it found it: a check that repaired what
  /// it measures would be green the second time for having changed the thing it judged.
  static const List<String> formatterArgv = <String>[
    'format',
    '--output=none',
    '--set-exit-if-changed',
    '.',
  ];

  @override
  Future<ToolRun> analyze({required String directory}) =>
      _capture(analyzerArgv, directory: directory);

  @override
  Future<ToolRun> format({required String directory}) =>
      _capture(formatterArgv, directory: directory);

  @override
  Future<int> runTests({required String directory}) =>
      _stream(<String>['test'], directory: directory);

  @override
  Future<int> runScript(String script, {required String directory}) =>
      _stream(<String>['run', script], directory: directory);

  @override
  Future<ToolRun> compileExecutable({
    required String directory,
    required String entryPoint,
    required String target,
  }) => _capture(<String>['compile', 'exe', entryPoint, '-o', target], directory: directory);

  @override
  Future<ToolRun> version({required String directory}) =>
      _capture(<String>['--version'], directory: directory);

  Future<ToolRun> _capture(List<String> arguments, {required String directory}) async {
    final ProcessResult result = await Process.run(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory,
      runInShell: false,
    );
    return ToolRun(exitCode: result.exitCode, output: '${result.stdout}${result.stderr}');
  }

  Future<int> _stream(List<String> arguments, {required String directory}) async {
    final Process process = await Process.start(
      Platform.resolvedExecutable,
      arguments,
      workingDirectory: directory,
      mode: ProcessStartMode.inheritStdio,
      runInShell: false,
    );
    return process.exitCode;
  }
}
