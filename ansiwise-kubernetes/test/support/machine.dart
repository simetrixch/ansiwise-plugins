import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';

/// A machine with a cluster in memory, and the context one step is asked its questions in.
final class ClusterMachine {
  /// A machine whose shell, files and clock are the given fakes, or fresh ones.
  ClusterMachine({FakeShell? shell, FakeFiles? files, FakeClock? clock})
    : shell = shell ?? FakeShell(),
      files = files ?? FakeFiles(),
      clock = clock ?? FakeClock();

  /// The commands and their scripted answers.
  final FakeShell shell;

  /// The files on the machine.
  final FakeFiles files;

  /// The clock a wait runs against.
  final FakeClock clock;

  /// Everything the log was told, so a test can assert what a step said about what it found.
  final List<String> said = <String>[];

  /// The context [step] is run in, with [arguments] where the step reads any.
  ///
  /// [answers] carries what an operator stated about the installation. A step reads its answers BY
  /// NAME out of the run, so a test for a step that reads one passes a bag carrying it.
  StepContext contextFor(
    StepName step, [
    Arguments arguments = Arguments.none,
    Arguments answers = Arguments.none,
  ]) => StepContext(
    shell: shell,
    files: files,
    http: FakeHttp(),
    clock: clock,
    entropy: FakeEntropy(),
    log: _CollectingLog(said),
    step: step,
    arguments: arguments,
    answers: answers,
    facts: Facts.none,
  );

  /// Every command that changed something, in the order it ran.
  List<String> get changing => <String>[
    for (final Command command in shell.commands)
      if (!command.observes) command.argv.join(' '),
  ];
}

final class _CollectingLog implements Logger {
  const _CollectingLog(this.said);

  final List<String> said;

  @override
  void debug(String message) => said.add(message);

  @override
  void info(String message) => said.add(message);

  @override
  void warn(String message) => said.add(message);

  @override
  void error(String message) => said.add(message);
}
