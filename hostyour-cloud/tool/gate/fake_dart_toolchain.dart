/// A toolchain that answers what a test told it to, and remembers what it was asked.
///
/// It ships beside the real one for the same reason the framework's fakes ship beside its ports: a
/// check that can only be exercised with the real tool installed is a check nobody can prove reads
/// the tool's answer correctly, because the only way to show that is to hand it an answer.
library;

import 'dart_toolchain.dart';

/// What one call to the toolchain was.
final class ToolCall {
  /// Records a call of [what] against the package in [directory].
  const ToolCall(this.what, this.directory);

  /// Which of the toolchain's questions was asked.
  final String what;

  /// The package it was asked about.
  final String directory;

  @override
  String toString() => '$what in $directory';
}

/// A toolchain with no `dart` behind it.
final class FakeDartToolchain implements DartToolchain {
  /// Creates a toolchain answering [answers], and a clean run for anything not named there.
  ///
  /// A key is either what was asked — `analyze`, `format`, `pub get` — or `<what> in <directory>`
  /// when one package of several has to answer differently.
  FakeDartToolchain({Map<String, ToolRun> answers = const <String, ToolRun>{}})
    : _answers = Map<String, ToolRun>.of(answers);

  final Map<String, ToolRun> _answers;

  /// Every call that was made, in order.
  final List<ToolCall> calls = <ToolCall>[];

  /// The exit code [runTests] and [runScript] answer.
  int streamedExitCode = 0;

  @override
  Future<ToolRun> pubGet({required String directory}) async => _answerFor('pub get', directory);

  @override
  Future<ToolRun> analyze({required String directory}) async => _answerFor('analyze', directory);

  @override
  Future<ToolRun> format({required String directory}) async => _answerFor('format', directory);

  @override
  Future<int> runTests({required String directory}) async {
    calls.add(ToolCall('test', directory));
    return streamedExitCode;
  }

  @override
  Future<int> runScript(String script, {required String directory}) async {
    calls.add(ToolCall('run $script', directory));
    return streamedExitCode;
  }

  @override
  Future<ToolRun> compileExecutable({
    required String directory,
    required String entryPoint,
    required String target,
  }) async => _answerFor('compile $entryPoint -> $target', directory);

  @override
  Future<ToolRun> version({required String directory}) async => _answerFor('--version', directory);

  ToolRun _answerFor(String what, String directory) {
    calls.add(ToolCall(what, directory));
    return _answers['$what in $directory'] ??
        _answers[what] ??
        const ToolRun(exitCode: 0, output: '');
  }
}
