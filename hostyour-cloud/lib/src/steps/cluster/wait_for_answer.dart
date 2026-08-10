import 'package:ansiwise_api/ansiwise_api.dart';

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
final class WaitForAnswer extends ObservingStep with WaitStep {
  /// Asks [command] every [intervalSeconds] until it writes [answer], for at most [timeoutSeconds].
  const WaitForAnswer({
    required this.waitingFor,
    required this.command,
    required this.commandArguments,
    required this.answer,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory WaitForAnswer.fromArguments(Arguments arguments) => WaitForAnswer(
    waitingFor: arguments.text('waiting_for'),
    command: arguments.text('command'),
    commandArguments: arguments.textList('command_arguments'),
    answer: arguments.text('answer'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
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
      describes: 'what is run each time this looks',
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
  ];

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

  @override
  Future<bool> holds(StepContext context) async {
    final CommandResult answered = await context.shell.run(
      Command.observing(command, commandArguments),
    );
    return answered.ok && answered.stdout.split('\n').any((String line) => line.trim() == answer);
  }
}
