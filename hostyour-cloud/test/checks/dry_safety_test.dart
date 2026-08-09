import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'dry_safety.dart';
import 'step_under_probe.dart';

Future<void> main() async {
  final DrySafety check = DrySafety(
    registry: executionRegistry,
    answers: await plausibleAnswers(const RealFiles(), 'programs'),
  );
  final DryRunReading reading = await check.askEveryStep();

  test('every registered step was asked what it would do', () {
    // A reading that covered no step would leave every assertion below unmade, and the check would
    // be green for having looked at nothing.
    expect(
      reading.outcomes,
      hasLength(executionRegistry.steps.length),
      reason: 'some step was never asked, so nothing about its dry run was measured',
    );
  });

  test('no registered step can complete a mutation under --mode dry', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          'each of these either produced a StepPlan or was refused by a port, and no command that '
          'changes something, no write, no delete and no request that is not a read reached the '
          'machine behind them',
    );
  });

  test(
    '${reading.safeCount} step(s) planned or were refused with nothing reaching the machine',
    () {
      expect(
        reading.safeCount,
        greaterThan(0),
        reason: 'not one step got as far as a plan or a refusal, so the ports were never exercised',
      );
    },
  );

  group('counter-probe', () {
    // Four steps written here, run through the same machinery. A step that writes from its check and
    // one that runs a changing command from its plan must both come back refused; a step that only
    // looks must come back with a plan, because a check that reported everything would satisfy the
    // first two alone.

    test('a write from inside a check is refused', () async {
      expect(
        await _ask(const WritesFromItsCheck(), wrapInPlanningPorts: true),
        isA<RefusedByAPort>(),
        reason: 'a step planted here wrote a file from its check and was not stopped',
      );
    });

    test('a changing command from inside a plan is refused', () async {
      expect(
        await _ask(const RunsAChangingCommandFromItsPlan(), wrapInPlanningPorts: true),
        isA<RefusedByAPort>(),
        reason: 'a step planted here ran a changing command from its plan and was not stopped',
      );
    });

    test('a step that only looks is left alone', () async {
      expect(
        await _ask(const OnlyLooks(), wrapInPlanningPorts: true),
        isA<ProducedAPlan>(),
        reason: 'a step planted here only read the machine and was reported anyway',
      );
    });

    // The one that matters most. It runs the writing step WITHOUT the planning ports, so the write
    // does reach the fake, and it fails unless that is reported. That is what separates "the ports
    // refused it" from "nothing was looking": weaken PlanningFiles.write from a refusal into a shrug
    // and the first test above goes red, delete the evidence-gathering and this one does.
    test('a mutation that got through is seen', () async {
      expect(
        await _ask(const WritesFromItsCheck(), wrapInPlanningPorts: false),
        isA<ReachedTheMachine>(),
        reason:
            'the same writing step ran with the planning ports taken off, the write reached the '
            'fake machine, and nothing noticed — so an empty finding proves nothing',
      );
    });

    test('the evidence names what reached the machine', () async {
      final DryRunOutcome outcome = await _ask(
        const WritesFromItsCheck(),
        wrapInPlanningPorts: false,
      );
      expect(
        (outcome as ReachedTheMachine).evidence,
        contains(contains(WritesFromItsCheck.path)),
        reason: 'a finding that does not say what was changed is one nobody can act on',
      );
    });
  });
}

Future<DryRunOutcome> _ask(Step step, {required bool wrapInPlanningPorts}) => askWhatItWouldDo(
  const StepName('planted'),
  step,
  Arguments.none,
  wrapInPlanningPorts: wrapInPlanningPorts,
);

/// A step that changes something from the one method a dry run always calls.
final class WritesFromItsCheck extends ReversibleStep {
  /// Creates the planted step.
  const WritesFromItsCheck();

  /// Where it writes, so a counter-probe can name what got through.
  static const String path = '/etc/planted';

  @override
  Future<CheckResult> check(StepContext context) async {
    await context.files.write(path, 'written from a check', mode: 0x180);
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.nothing('never reached, because the check writes first');

  @override
  Future<void> apply(StepContext context) async {}

  @override
  Future<void> undo(StepContext context) async {}
}

/// A step that changes something from the method a dry run calls instead of `apply`.
final class RunsAChangingCommandFromItsPlan extends ReversibleStep {
  /// Creates the planted step.
  const RunsAChangingCommandFromItsPlan();

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async {
    await context.shell.run(const Command('rm', <String>['-rf', '/planted']));
    return const StepPlan.argv(<String>['rm', '-rf', '/planted']);
  }

  @override
  Future<void> apply(StepContext context) async {}

  @override
  Future<void> undo(StepContext context) async {}
}

/// A step that reads the machine and plans, which is what every step is meant to do.
final class OnlyLooks extends ReversibleStep {
  /// Creates the planted step.
  const OnlyLooks();

  @override
  Future<CheckResult> check(StepContext context) async {
    await context.files.exists('/etc/planted');
    await context.shell.run(const Command.observing('true'));
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff('/etc/planted', before: '', after: 'what this step would write');

  @override
  Future<void> apply(StepContext context) async {}

  @override
  Future<void> undo(StepContext context) async {}
}
