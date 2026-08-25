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
    shell: _Cluster(shell, _unreachable, _absent),
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

  /// Makes every reading of [kind] answer as a cluster nothing can reach, saying [stderr].
  ///
  /// **Both readings, and that is the point.** A step asking about one named object makes two: the
  /// GET of the object, and the LIST of the kind that says whether the cluster answered at all. A
  /// cluster that is not there refuses both; a cluster that answers and holds no such object refuses
  /// only the first, which is [holdingNo].
  ///
  /// Matched on the words up to the kind rather than on a whole command line, because the get
  /// carries whatever output the step asked for — a fixture spelling that out is a second copy of
  /// the step's own composition, and it answers happily after the step stops asking that way.
  void cannotBeReached(String kind, {String? namespace, required String stderr}) =>
      _unreachable['kubectl ${namespace == null ? '' : '-n $namespace '}get $kind'] = stderr;

  /// Makes [kind] read as a kind the cluster serves and holds none of.
  ///
  /// The GET of the named object fails the way the client refuses one that is not there, and the
  /// LIST answers empty at exit zero — which is what a list does for a cluster holding none.
  void holdingNo(String kind, {String? namespace, required String stderr}) =>
      _absent['kubectl ${namespace == null ? '' : '-n $namespace '}get $kind'] = stderr;

  /// The readings that answer as a cluster nothing can reach, by the words they begin with.
  final Map<String, String> _unreachable = <String, String>{};

  /// The kinds the cluster serves and holds none of, by the words their readings begin with.
  final Map<String, String> _absent = <String, String>{};
}

/// The cluster's shell, with the readings [_unreachable] names answered as a cluster nothing can
/// reach.
///
/// A prefix and not a whole command line: see [ClusterMachine.cannotBeReached]. Everything else goes
/// to the fake beside it, so a case that scripted an answer keeps it.
final class _Cluster implements Shell {
  const _Cluster(this._shell, this._unreachable, this._absent);

  final FakeShell _shell;
  final Map<String, String> _unreachable;
  final Map<String, String> _absent;

  @override
  Future<CommandResult> run(Command command) async {
    final String argv = command.argv.join(' ');
    for (final MapEntry<String, String> refused in _unreachable.entries) {
      if (_beginsWith(argv, refused.key)) {
        return _refusing(command, refused.value);
      }
    }
    for (final MapEntry<String, String> none in _absent.entries) {
      // The LIST answers and only the get of a named object does not, and that IS the difference
      // between a kind the cluster serves and holds none of, and a cluster nobody could ask.
      if (argv == '${none.key} -o name') {
        await _shell.run(command);
        return const CommandResult(exitCode: 0, stdout: '', stderr: '', elapsed: Duration.zero);
      }
      if (_beginsWith(argv, none.key)) {
        return _refusing(command, none.value);
      }
    }
    return _shell.run(command);
  }

  static bool _beginsWith(String argv, String words) => argv == words || argv.startsWith('$words ');

  /// Answers [said] at exit one, having recorded the command the way every other one is recorded.
  Future<CommandResult> _refusing(Command command, String said) async {
    await _shell.run(command);
    return CommandResult(exitCode: 1, stdout: '', stderr: '$said\n', elapsed: Duration.zero);
  }
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
