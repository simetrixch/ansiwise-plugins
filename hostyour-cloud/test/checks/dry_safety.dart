/// dry-safety — no registered step can change anything under `--mode dry`.
///
/// This is the property the whole framework was chosen for. The shell implementation it replaces held
/// hundreds of places that could change a machine, and no amount of review could show that none of
/// them fires when somebody asks for a dry run. Here it is decided by running every step.
///
/// WHAT IS DRIVEN. A step's `check`, its `plan`, and — for a reversible one — its `capture`. The
/// third is the one nobody would think to look at: it runs in every mode, because an undo has to be
/// handed what was there whether or not the run turns out to need it, and it is preparation for
/// taking work back rather than the work itself.
///
/// THE GUARANTEE RESTS ON TWO INDEPENDENT THINGS, and this check drives the second. The engine calls
/// a step's `plan` and never its `apply`; and the ports a step is given under a dry run —
/// `PlanningShell`, `PlanningFiles`, `PlanningHttp` — throw [MutationRefused] on anything the step did
/// not declare as only looking. The second is what holds when the first is wrong: when a check reaches
/// for something it should not, when a plan computes its difference by writing a temporary file, when
/// a helper three calls down grew a side effect nobody noticed in review.
///
/// WHAT IS ASSERTED IS NOT WHAT THE STEP RETURNED. The planning ports are put around fakes and the
/// FAKES are read afterwards: a step that quietly succeeded while writing did not go through a port
/// that refuses, and only the machine underneath can say so.
///
/// The exec-confinement check is the other side of this and neither replaces the other: that one
/// keeps a step from leaving the framework at all, this one shows that what stays inside is refused.
/// A step could pass either alone.
library;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';

import 'finding.dart';
import 'step_under_probe.dart';

/// What one step did when a dry run asked it to check and to plan.
sealed class DryRunOutcome {
  const DryRunOutcome();
}

/// It said what it would change, and changed nothing.
final class ProducedAPlan extends DryRunOutcome {
  /// Records the plan it produced.
  const ProducedAPlan(this.summary);

  /// The plan in one line, as the operator would read it.
  final String summary;

  @override
  String toString() => 'planned: $summary';
}

/// A planning port stopped it, and nothing reached the machine behind them.
final class RefusedByAPort extends DryRunOutcome {
  /// Records what was refused.
  const RefusedByAPort(this.what);

  /// What it tried to do.
  final String what;

  @override
  String toString() => 'refused while planning: $what';
}

/// Something that changes the machine got through.
final class ReachedTheMachine extends DryRunOutcome {
  /// Records everything that reached the fake machine, in the order it happened.
  const ReachedTheMachine(this.evidence);

  /// What was found on the fakes afterwards.
  final List<String> evidence;

  @override
  String toString() => 'reached the machine: ${evidence.join('; ')}';
}

/// It neither produced a plan nor was refused, so what it would do is unknown.
final class NeitherPlannedNorRefused extends DryRunOutcome {
  /// Records what happened instead.
  const NeitherPlannedNorRefused(this.what);

  /// What it did answer.
  final String what;

  @override
  String toString() => 'neither planned nor was refused: $what';
}

/// Every registered step, asked what it would do, with the ports a dry run hands out.
final class DrySafety {
  /// Asks every step of [registry], giving each the values in [answers] for what a program declares.
  const DrySafety({required this.registry, this.answers = Arguments.none});

  /// The registry whose steps are asked.
  final Registry registry;

  /// A value for every answer any program file declares.
  ///
  /// Read from the program files rather than listed, because a step reads an answer by name and only
  /// a program declares what kind of value that name holds. A check handing every step an empty bag
  /// would report a whole area as steps whose check threw, which reads as a defect in the steps
  /// rather than in the check.
  final Arguments answers;

  /// What each step did, by the name a program file writes.
  Future<DryRunReading> askEveryStep() async {
    final Map<String, DryRunOutcome> outcomes = <String, DryRunOutcome>{};
    final List<Finding> problems = <Finding>[];
    for (final MapEntry<StepName, RegisteredStep> pair in registry.steps.entries) {
      final Step? step = buildStep(pair.value, problems.add);
      if (step == null) {
        continue;
      }
      outcomes[pair.key.value] = await askWhatItWouldDo(
        pair.key,
        step,
        plausibleArguments(pair.value.arguments),
        answers: answers,
        wrapInPlanningPorts: true,
      );
    }
    return DryRunReading(outcomes: outcomes, problems: problems);
  }
}

/// What a whole registry did under a dry run.
final class DryRunReading {
  /// Records the outcome of every step that could be built, and what could not.
  const DryRunReading({required this.outcomes, required this.problems});

  /// What each step did, by the name a program file writes.
  final Map<String, DryRunOutcome> outcomes;

  /// Steps nothing could be measured about.
  final List<Finding> problems;

  /// How many steps produced a plan or were refused with nothing reaching the machine.
  int get safeCount => outcomes.values
      .where((DryRunOutcome outcome) => outcome is ProducedAPlan || outcome is RefusedByAPort)
      .length;

  /// Everything a dry run of this registry would do that it must not.
  List<Finding> get findings => <Finding>[
    ...problems,
    for (final MapEntry<String, DryRunOutcome> pair in outcomes.entries)
      if (pair.value case ReachedTheMachine(:final List<String> evidence))
        Finding(pair.key, 'a dry run of this step reached the machine — ${evidence.join('; ')}')
      else if (pair.value case NeitherPlannedNorRefused(:final String what))
        Finding(
          pair.key,
          'a dry run neither produced a plan nor was refused, so what it would do '
          'is unknown — $what',
        ),
  ];
}

/// Asks [step] to check and to plan, and reports what reached the machine while it did.
///
/// `plan` is asked even where `check` did not answer [Ready]. The engine only plans a step that is
/// ready, but which of the two a step is asked depends on a machine this check does not have, and a
/// mutation inside a plan that this tree's fakes never make ready is a mutation waiting for the
/// machine that does.
///
/// [wrapInPlanningPorts] is what a counter-probe turns off. With the wrappers gone the fakes carry
/// the mutation out, and the outcome must then be [ReachedTheMachine] — which is the only way to show
/// that a clean answer means the ports refused rather than that nobody was looking.
Future<DryRunOutcome> askWhatItWouldDo(
  StepName name,
  Step step,
  Arguments arguments, {
  required bool wrapInPlanningPorts,
  Arguments answers = Arguments.none,
}) async {
  final FakeShell shell = FakeShell();
  final FakeFiles files = FakeFiles();
  final FakeHttp http = FakeHttp();

  final StepContext context = probeContext(
    step: name,
    arguments: arguments,
    answers: answers,
    shell: wrapInPlanningPorts ? PlanningShell(shell, step: name) : shell,
    files: wrapInPlanningPorts ? PlanningFiles(files, step: name) : files,
    http: wrapInPlanningPorts ? PlanningHttp(http, step: name) : http,
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: CollectedLog(),
  );

  bool refused = false;
  String what = '';
  StepPlan? plan;

  try {
    what = describeCheck(await step.check(context));
  } on MutationRefused catch (refusal) {
    refused = true;
    what = refusal.what;
  } on Object catch (failure) {
    what = 'its check threw $failure';
  }

  if (!refused) {
    try {
      plan = await step.plan(context);
    } on MutationRefused catch (refusal) {
      refused = true;
      what = refusal.what;
    } on Object catch (failure) {
      what = 'its plan threw $failure';
    }
  }

  // The capture too, and it is the one nobody would suspect. It runs in EVERY mode, including the
  // two that change nothing, because an undo has to be handed what was there whether or not the run
  // turns out to need it. A capture that reached for something — read a file by writing a temporary
  // one, asked a tool that mutates on its way to answering — would break the dry-run guarantee at
  // the one place nobody looks, because it is not the step's own work but the preparation for
  // taking that work back.
  if (!refused && step is ReversibleStep<Object?>) {
    try {
      await step.capture(context);
    } on MutationRefused catch (refusal) {
      refused = true;
      what = refusal.what;
    } on Object catch (failure) {
      what = 'its capture threw $failure';
    }
  }

  final List<String> reached = _whatChangedTheMachine(shell: shell, files: files, http: http);
  if (reached.isNotEmpty) {
    return ReachedTheMachine(reached);
  }
  if (refused) {
    return RefusedByAPort(what);
  }
  if (plan case final StepPlan produced) {
    return ProducedAPlan(produced.summary);
  }
  return NeitherPlannedNorRefused(what);
}

/// Everything that changed the fake machine, read off the fakes rather than off the step.
///
/// A command counts as changing something unless it says it only observes, which is the default the
/// framework chose: a command nobody thought about is treated as a mutation. A request is read the
/// same way from its method, since [FakeHttp] records `METHOD url`.
List<String> _whatChangedTheMachine({
  required FakeShell shell,
  required FakeFiles files,
  required FakeHttp http,
}) => <String>[
  for (final Command command in shell.commands)
    if (!command.observes) 'ran ${command.argv.join(' ')}',
  for (final String path in files.written) 'wrote $path',
  for (final String path in files.deleted) 'deleted $path',
  for (final String path in files.directories) 'created the directory $path',
  for (final String request in http.sent)
    if (!onlyReads(request)) 'sent $request',
];

/// Whether a `METHOD url` recorded by [FakeHttp] only reads.
bool onlyReads(String request) =>
    request.startsWith('GET ') || request.startsWith('HEAD ') || request.startsWith('OPTIONS ');
