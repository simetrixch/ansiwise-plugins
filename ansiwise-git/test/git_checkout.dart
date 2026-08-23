/// One fake checkout, arranged the way a healthy one answers, for every test of this package.
///
/// The three steps ask the same checkout different questions, so the arrangement is written once
/// here rather than per file: a second copy would answer one file's questions and slowly stop
/// answering the other's, and a step would then be measured against a machine nobody meant.
library;

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';

/// The checkout every case is run against.
const String repository = '/srv/checkout';

/// What a new branch is cut from, and what a push is offered for.
const String base = 'master';

/// The name this checkout holds its remote under.
const String remote = 'origin';

/// The name of the answer the branch name is read out of.
///
/// Deliberately not a word any product of ours uses. The step is told which answer to read by its
/// row, so a test naming the product's own word would pass even if the step ignored the row and
/// reached for that word itself.
const String nameAnswer = 'branch_name';

/// What this run answers for [nameAnswer], which becomes the branch that is cut.
const String branch = 'm1.example.com';

/// A run holding [name] under [answerName], against the machine [shell] describes.
///
/// A null [name] is a run that holds no such answer at all, which is what a program declaring
/// nothing under the name its row points at produces. [answerName] varies where a case is about the
/// row choosing which answer to read.
///
/// [also] is for the rows that read MORE THAN ONE answer — a checkout naming both which repository
/// it is from and which branch it stands on. A case stating one of the two and not the other is
/// what proves each is read on its own, so they are separate rather than one map.
/// [log] is for the cases where what a step SAYS is the thing being measured. It defaults to the
/// one that keeps nothing, so a case that is about the machine is not made to arrange a log.
StepContext contextOn({
  FakeShell? shell,
  FakeFiles? files,
  String? name = branch,
  String answerName = nameAnswer,
  Map<String, Object> also = const <String, Object>{},
  Logger log = const SilentLog(),
}) => StepContext(
  shell: shell ?? FakeShell(),
  files: files ?? FakeFiles(),
  http: FakeHttp(),
  clock: FakeClock(),
  entropy: FakeEntropy(),
  log: log,
  step: const StepName('under_test'),
  arguments: Arguments.none,
  // The branch name is an ANSWER: nobody can write one into a file that ships to every machine, so
  // it varies per case here rather than per step instance.
  answers: Arguments(<String, Object>{answerName: ?name, ...also}),
  facts: Facts.none,
);

/// A checkout that answers every question these steps ask, the way a healthy one would.
FakeShell checkout({
  String head = base,
  String status = '',
  bool branchExists = false,
  String name = branch,
}) {
  final FakeShell shell = FakeShell()
    ..answers('git -C $repository rev-parse --git-dir', '.git\n')
    ..answers('git -C $repository config --get user.name', 'Example Operator\n')
    ..answers('git -C $repository config --get user.email', 'operator@example.com\n')
    ..answers('git -C $repository remote get-url $remote', 'git@example.com:example/tree.git\n')
    ..answers('git -C $repository ls-remote --heads $remote', 'abc\trefs/heads/$base\n')
    ..answers('git -C $repository push --dry-run $remote $base', '')
    ..answers('git check-ref-format --branch $name', '$name\n')
    ..answers('git -C $repository rev-parse --abbrev-ref HEAD', '$head\n')
    ..answers('git -C $repository status --porcelain', status);
  if (branchExists) {
    shell.answers('git -C $repository rev-parse --verify --quiet refs/heads/$name', 'abc\n');
  } else {
    shell.fails('git -C $repository rev-parse --verify --quiet refs/heads/$name');
  }
  return shell;
}

/// A log that keeps nothing, so a step's own notes do not land in the middle of a test run.
final class SilentLog implements Logger {
  /// Creates the log.
  const SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// A log that keeps what it was given, for the cases where what a step SAYS is the thing measured.
///
/// A step whose only observable effect is a line in the record has no probe at all against a log
/// that throws its lines away — the case would go in unmeasured and read like coverage.
final class RecordingLog implements Logger {
  /// Creates the log.
  RecordingLog();

  /// Every warning, in the order it was written.
  final List<String> warnings = <String>[];

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) => warnings.add(message);

  @override
  void error(String message) {}
}
