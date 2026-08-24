import 'package:ansiwise_core/ansiwise_core.dart';

/// Waits until a command answers what it should.
///
/// A wait is three decisions and nothing else: which command to ask, which answer means yes, and how
/// long to keep asking. All three stand in the program file, so something new to wait for is a row
/// rather than a class — and every wait then reaches its deadline the same way and says the same
/// kind of thing when it does.
///
/// **BOTH have to hold: the command succeeded, and it wrote the answer.** A zero exit code on its
/// own proves nothing — a command that returned zero and said nothing is not a yes, which is why
/// the output decides. But a command that FAILED has not answered at all, and reading a yes out of
/// what a failed command happened to print is reporting success over a real failure, which is the
/// one thing this framework exists to end.
///
/// Both directions cost something and they are not the same size. Requiring the exit code turns a
/// command that fails while printing the answer into a wait that reaches its deadline — recorded,
/// loud, and fixed by correcting the row. Not requiring it turns a command that failed into a
/// silent yes. The second cannot be repaid once it has been relied on.
///
/// **The answer has to be a WHOLE LINE of that output**, with the spaces around it removed, and
/// never a part of one. A status that lists what is off underneath what is on is the case that
/// decides this: a search for a name somewhere in the output finds it in the second list and reports
/// the thing as on at the very moment it was switched off.
///
/// **A command that says nothing has not said yes.** Something just asked for often carries no
/// status at all yet, which reads as empty output rather than as a no — and treating that as an
/// error would fail on the one state this exists to sit through.
///
/// **[waitingFor] is what a reached deadline reports**, so a program row has to give it: the failure
/// reads `waited 300s for <this> and it did not happen`, and whoever reads that line has to learn
/// from it which thing did not happen.
final class WaitForCommandOutput extends ObservingStep with WaitStep {
  /// Asks [command] every [intervalSeconds] until it writes [answer], for at most [timeoutSeconds].
  const WaitForCommandOutput({
    required this.waitingFor,
    required this.command,
    required this.commandArguments,
    required this.answer,
    required this.timeoutSeconds,
    required this.intervalSeconds,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory WaitForCommandOutput.fromArguments(Arguments arguments) => WaitForCommandOutput(
    waitingFor: arguments.text('waiting_for'),
    command: arguments.text('command'),
    commandArguments: arguments.textList('command_arguments'),
    answer: arguments.text('answer'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'waiting_for',
      kind: ArgumentKind.text,
      describes:
          'what is being waited for, named so a deadline that is reached says what did not '
          'happen',
    ),
    ArgumentSpec(
      name: 'command',
      kind: ArgumentKind.text,
      describes:
          'what is run each time this looks — it must only look, and the run takes the row\'s '
          'word for that, so the record marks this row declared rather than proven',
    ),
    ArgumentSpec(
      name: 'command_arguments',
      kind: ArgumentKind.textList,
      describes: 'what is passed to it, each argument as its own entry',
      required: false,
      defaultValue: <String>[],
    ),
    ArgumentSpec(
      name: 'answer',
      kind: ArgumentKind.text,
      describes: 'the line the command has to write for the wait to be over',
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long it is given before the wait reports that it did not happen',
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks',
    ),
    // ASKED, never guessed. Whether the thing being polled answers an ordinary account is a
    // property of that thing, and this step has no way to know it — a command that refuses for
    // want of permission usually says so on its output and exits ZERO, so what this step sees is
    // simply an answer that is not the one it waits for. It then waits out the whole window and
    // reports that the thing never happened, which is a true sentence about the wrong subject.
    //
    // Measured exactly that way: a cluster was up and answering within minutes, the poll ran as an
    // account not in the group that may ask it, and the run gave up after fifteen minutes saying
    // the node never reported itself running.
    ArgumentSpec(
      name: 'elevated',
      kind: ArgumentKind.flag,
      describes:
          'whether the command has to run as root to READ what it reports. Running as root changes '
          'nothing, so a poll that needs it is still something a dry run may perform',
      required: false,
    ),
  ];

  /// Whether the poll runs as root, because what it asks refuses an ordinary account.
  final bool elevated;

  /// What is being waited for, in the words the failure reports.
  @override
  final String waitingFor;

  /// What is run each time this looks.
  ///
  /// The executable on its own rather than the first entry of a list, which is how the framework
  /// describes a command: a row that names no command at all cannot be written down.
  final String command;

  /// What is passed to it, each argument as its own entry.
  final List<String> commandArguments;

  /// The line the command has to write.
  final String answer;

  /// How long it is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  @override
  Duration get deadline => Duration(seconds: timeoutSeconds);

  @override
  Duration get interval => Duration(seconds: intervalSeconds);

  /// The room a poll's command has beyond the wait's own budget.
  ///
  /// Every poll carries a deadline, or one command that blocks hangs the whole run: the wait's own
  /// budget is only checked BETWEEN polls, so it never interrupts a call that does not return. And
  /// the kill has to LOSE the race against any command that answers within the row's timeout — a
  /// command that waits and reports on its own must get to say its own last word, because that
  /// message is what the operator reads, and "killed" is not it.
  static const Duration _grace = Duration(seconds: 30);

  /// The command comes from the row, and nothing here chose it — so the framework cannot verify
  /// the row's claim that it only looks. The step says so instead of claiming it: every row of
  /// this step is recorded as declared rather than proven, the run's closing numbers carry it, and
  /// the dry-safety check lists this step instead of counting it safe.
  @override
  bool get answersOnTrust => true;

  @override
  Future<({bool held, String? saw})> holds(StepContext context) async {
    final CommandResult answered = await context.shell.run(
      // Observing on the row's word — the obligation stands at the command argument — and never
      // without a deadline: a poll that blocks is killed at the row's timeout plus the grace,
      // which turns a wedged command into a loud failure instead of a run nothing interrupts.
      Command.detailed(
        command,
        arguments: commandArguments,
        observes: true,
        elevated: elevated,
        timeout: deadline + _grace,
      ),
    );
    if (answered.ok && answered.stdout.split('\n').any((String line) => line.trim() == answer)) {
      return (held: true, saw: null);
    }
    // WHAT THE MACHINE SAID INSTEAD, which is the whole reason this is not a bare false. A command
    // that ran and printed something other than the answer knows more than the clock does: the
    // reading this was written for was a certificate authority refusing a mailbox by name,
    // available one second in and thrown away for sixty. Standard error first, because a command
    // that failed puts its reason there; the output otherwise, because a command that succeeded and
    // said the wrong thing puts it there.
    final String reading = (answered.stderr.trim().isNotEmpty ? answered.stderr : answered.stdout)
        .split('\n')
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .join(' ');
    return (
      held: false,
      saw: reading.isEmpty
          ? 'the command answered nothing at all'
          : 'it said "$reading" and not "$answer"',
    );
  }
}
