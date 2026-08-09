/// idempotence — a second run of a step does nothing.
///
/// This is what every deployment tool sells and few prove. The shape it takes here is exact: the
/// step's `check` answers [Satisfied] the second time, BEFORE any work, so the engine never calls
/// `apply` again. A program that is not idempotent is a program nobody dares run twice, and every
/// real deployment is run twice.
///
/// THE INTERESTING PART IS WHAT THIS CANNOT SEE, and it decides the shape of the whole check. Each
/// step runs against a fake machine. `FakeFiles` is a file system: a step whose `apply` writes is
/// genuinely applied, and its second check reads what the first one wrote. `FakeShell` is a table of
/// answers — it records a command and does not carry it out — so a step whose postcondition a real
/// command would leave behind runs on a machine where that postcondition never becomes true. Its
/// second check then answers the same as its first, for a reason that has nothing to do with the step.
///
/// A STEP COUNTED AS PASSING BECAUSE THE FAKE COULD NOT EXERCISE IT IS THE FAILURE THIS CHECK EXISTS
/// TO PREVENT. So there is no bucket that means "probably fine". Every step lands in exactly one of
/// [Exercised], [OnlyMeasures], [NotCovered] and [WouldRepeat], and a [NotCovered] step is named in
/// a ledger the test asserts against — only a fixture arranged for that particular step closes one.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';

import 'dry_safety.dart';
import 'finding.dart';
import 'step_fixtures.dart';
import 'step_under_probe.dart';

/// What running one step twice showed.
sealed class Coverage {
  const Coverage(this.why);

  /// What was seen, in the words a person reads beside the step's name.
  final String why;
}

/// Applied against the fake machine, and the second check answered [Satisfied].
final class Exercised extends Coverage {
  /// Records that the second run had nothing to do.
  const Exercised(super.why);

  @override
  String toString() => 'exercised: $why';
}

/// A step that only measures: it changes nothing on any run, and answered the same twice.
final class OnlyMeasures extends Coverage {
  /// Records that it measured the same thing twice.
  const OnlyMeasures(super.why);

  @override
  String toString() => 'observing: $why';
}

/// The fake machine could not exercise it, and this says why not.
final class NotCovered extends Coverage {
  /// Records why the fake machine could not exercise it.
  const NotCovered(super.why);

  @override
  String toString() => 'NOT COVERED: $why';
}

/// A second run would do the work again.
final class WouldRepeat extends Coverage {
  /// Records what the second run would do.
  const WouldRepeat(super.why);

  @override
  String toString() => 'repeats: $why';
}

/// Every registered step, run twice against one fake machine.
final class Idempotence {
  /// Runs every step of [registry], arranging the fake with [fixtures] where there is one.
  const Idempotence({
    required this.registry,
    required this.fixtures,
    this.answers = Arguments.none,
  });

  /// The registry whose steps are run.
  final Registry registry;

  /// A value for every answer any program file declares.
  final Arguments answers;

  /// The fake machine each named step meets.
  final Map<String, Fixture> fixtures;

  /// What each step did on its second run, by the name a program file writes.
  Future<IdempotenceReading> runEveryStep() async {
    final Map<String, Coverage> coverage = <String, Coverage>{};
    final List<Finding> problems = <Finding>[];
    for (final MapEntry<StepName, RegisteredStep> pair in registry.steps.entries) {
      final Step? step = buildStep(pair.value, problems.add);
      if (step == null) {
        continue;
      }
      coverage[pair.key.value] = await runTwice(
        pair.key,
        step,
        plausibleArguments(pair.value.arguments),
        answers: answers,
        fixture: fixtures[pair.key.value],
      );
    }
    return IdempotenceReading(coverage: coverage, problems: problems);
  }
}

/// What a whole registry did on its second run.
final class IdempotenceReading {
  /// Records the coverage of every step that could be built, and what could not.
  const IdempotenceReading({required this.coverage, required this.problems});

  /// What each step did, by the name a program file writes.
  final Map<String, Coverage> coverage;

  /// Steps nothing could be measured about.
  final List<Finding> problems;

  /// The steps a fake machine could not exercise, sorted.
  ///
  /// Not a pass and not a failure: a step nothing here has shown anything about.
  List<String> get notCoveredNames => _namesOf<NotCovered>();

  /// The steps that were applied and then answered satisfied, sorted.
  List<String> get exercisedNames => _namesOf<Exercised>();

  /// The steps that only measure, sorted.
  List<String> get observingNames => _namesOf<OnlyMeasures>();

  /// Every step whose second run would do the work again.
  List<Finding> get findings => <Finding>[
    ...problems,
    for (final MapEntry<String, Coverage> pair in coverage.entries)
      if (pair.value case WouldRepeat(:final String why))
        Finding(pair.key, 'a second run would do the work again — $why'),
  ];

  List<String> _namesOf<T extends Coverage>() {
    final List<String> names = <String>[
      for (final MapEntry<String, Coverage> pair in coverage.entries)
        if (pair.value is T) pair.key,
    ];
    return names..sort();
  }
}

/// Runs [step] twice against one fake machine and decides which of the four it is.
///
/// [fixture] arranges the fake the way the real machine would be arranged. Without it most steps
/// cannot be measured at all: a fake shell records a command and does not carry it out, so a
/// postcondition left behind by a command never becomes true.
Future<Coverage> runTwice(
  StepName name,
  Step step,
  Arguments arguments, {
  Arguments answers = Arguments.none,
  Fixture? fixture,
}) async {
  final FakeShell shell = FakeShell();
  final FakeFiles files = FakeFiles();
  final FakeHttp http = FakeHttp();

  fixture?.call(shell, files, http);
  final StepContext context = probeContext(
    step: name,
    arguments: arguments,
    answers: answers,
    shell: shell,
    files: files,
    http: http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: CollectedLog(),
  );

  // A step that only measures changes nothing on any run, so the question is whether it ANSWERS the
  // same twice. One that does not is reading something about the machine that moved while nothing was
  // done to it, and a program built on it would take a different branch on every run.
  if (step is ObservingStep) {
    final String first = await _check(step, context);
    final String again = await _check(step, context);
    if (first != again) {
      return WouldRepeat(
        'it only measures, and it answered "$first" and then "$again" on a machine nothing was done '
        'to',
      );
    }
    return OnlyMeasures('it changes nothing, and answered "$first" both times');
  }

  final CheckResult first;
  try {
    first = await step.check(context);
  } on Object catch (failure) {
    return NotCovered('its first check threw $failure on a fake machine');
  }

  switch (first) {
    case Blocked(:final String reason):
      return NotCovered(
        'a fake machine does not meet its preconditions, so it was never applied — $reason',
      );
    case Satisfied(:final String because):
      return NotCovered(
        'a fake machine already satisfies it, so the step from having work to having none was never '
        'seen — $because',
      );
    case Ready():
      break;
  }

  try {
    await step.apply(context);
  } on Object catch (failure) {
    return NotCovered('its apply threw $failure on a fake machine');
  }

  // What the fake cannot carry out. A recorded command and a sent request leave the fake machine
  // exactly as it was, so a postcondition that a real one of either would have produced can never
  // become true here — and the second check is then answering about a machine on which the work did
  // not happen, whatever the step is like.
  final List<String> notCarriedOut = <String>[
    // A command the fake was ARRANGED to carry out did change this machine — that is what
    // FakeShell.changes is for, and it is how a fixture makes a postcondition actually become true.
    // Only a command with no effect behind it leaves the fake as it was.
    for (final Command command in shell.commands)
      if (!command.observes && !shell.carriedOut.contains(command.argv.join(' ')))
        'the fake shell recorded "${command.argv.join(' ')}" and ran nothing',
    for (final String request in http.sent)
      if (!onlyReads(request)) 'the fake network recorded "$request" and sent nothing',
  ];
  if (notCarriedOut.isNotEmpty) {
    return NotCovered(notCarriedOut.join('; '));
  }

  final String changed = files.written.isEmpty
      ? 'its apply changed nothing'
      : 'its apply wrote ${files.written.join(', ')}';

  final CheckResult second;
  try {
    second = await step.check(context);
  } on Object catch (failure) {
    return NotCovered('its second check threw $failure on a fake machine');
  }

  if (second case Satisfied(:final String because)) {
    return Exercised('$changed, and the second check answered satisfied — $because');
  }
  return WouldRepeat(
    '$changed, and the second check answered "${describeCheck(second)}" instead of satisfied, so the '
    'work would be done again',
  );
}

Future<String> _check(Step step, StepContext context) async {
  try {
    return describeCheck(await step.check(context));
  } on Object catch (failure) {
    return 'threw $failure';
  }
}
