import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

Future<void> main() async {
  final DrySafety check = DrySafety(
    registry: vaultRegistry,
    answers: (await answersDeclaredBy(vaultRegistry)).values,
  );
  final DryRunReading reading = await check.askEveryStep();

  test('every registered step was asked what it would do', () {
    // A reading that covered no step would leave every assertion below unmade, and the check would
    // be green for having looked at nothing.
    expect(
      reading.outcomes,
      hasLength(vaultRegistry.steps.length),
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

  test("the steps that answer on the row's word are listed, and are not counted safe", () {
    // For such a step the dry-run guarantee is the row's claim, not the framework's: the row names
    // the command and declares that it only looks, and nothing here chose or verified it. So the
    // check states the list for somebody to read instead of counting them among the safe ones —
    // this assertion is exact, so a new step that takes the row's word has to be named here to
    // pass. No step of this package does today.
    expect(
      reading.onTrust,
      isEmpty,
      reason:
          'either a step whose answer rests on the row went uncounted, or one was counted safe '
          'on a claim the framework cannot verify',
    );
  });

  group('counter-probe', () {
    // Four steps written here, run through the same machinery, one per method a dry run drives. A
    // step that writes from its check, one that runs a changing command from its plan and one that
    // writes from its CAPTURE must all three come back refused; a step that only looks must come
    // back with a plan, because a check that reported everything would satisfy the first three
    // alone.

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

    // The request half, and this package is the one that needs it: its steps reach a tool over
    // HTTP rather than through a shell, so a mutation of theirs is a POST and not a command.
    test('a request that is not a read is refused', () async {
      expect(
        await _ask(const SendsARequestFromItsPlan(), wrapInPlanningPorts: true),
        isA<RefusedByAPort>(),
        reason: 'a step planted here sent a POST from its plan and was not stopped',
      );
    });

    test('a request that got through is seen', () async {
      expect(
        await _ask(const SendsARequestFromItsPlan(), wrapInPlanningPorts: false),
        isA<ReachedTheMachine>(),
        reason:
            'the same step ran with the planning ports taken off, the request reached the fake '
            'machine, and nothing noticed',
      );
    });

    test('a write from inside a capture is refused', () async {
      expect(
        await _ask(const WritesFromItsCapture(), wrapInPlanningPorts: true),
        isA<RefusedByAPort>(),
        reason: 'a step planted here wrote a file from its capture and was not stopped',
      );
    });

    // What says the capture is DRIVEN at all, and not merely refused-by-absence. With the planning
    // ports off the write reaches the fake, so this is red both when the ports stop refusing and
    // when the audit stops calling `capture` — and the test above cannot tell those apart on its
    // own, because a capture nobody calls also produces no finding.
    test('a capture that got through is seen', () async {
      expect(
        await _ask(const WritesFromItsCapture(), wrapInPlanningPorts: false),
        isA<ReachedTheMachine>(),
        reason:
            'the capture ran with the planning ports taken off and nothing noticed — so either the '
            'evidence is not gathered or the capture is never driven',
      );
    });

    test("a step that answers on the row's word is reported as on trust, not as safe", () async {
      expect(
        await _ask(const AnswersOnTheRowsWord(), wrapInPlanningPorts: true),
        isA<AnsweredOnTrust>(),
        reason:
            'a step planted here says its answer rests on the row and came back counted as an '
            'ordinary plan, so the list an operator reads would miss it',
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
final class WritesFromItsCheck extends IrreversibleStep {
  /// Creates the planted step.
  const WritesFromItsCheck();

  /// Where it writes, so a counter-probe can name what got through.
  static const String path = '/etc/planted';

  @override
  String get irreversibleReason => 'it is a probe and is never run against a machine';

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
}

/// A step that changes something from the method a dry run calls instead of `apply`.
final class RunsAChangingCommandFromItsPlan extends IrreversibleStep {
  /// Creates the planted step.
  const RunsAChangingCommandFromItsPlan();

  @override
  String get irreversibleReason => 'it is a probe and is never run against a machine';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async {
    await context.shell.run(const Command('rm', <String>['-rf', '/planted']));
    return const StepPlan.argv(<String>['rm', '-rf', '/planted']);
  }

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step that changes something over HTTP, which is how every step of this package reaches its
/// tool.
final class SendsARequestFromItsPlan extends IrreversibleStep {
  /// Creates the planted step.
  const SendsARequestFromItsPlan();

  /// Where it posts, so a counter-probe can name what got through.
  static const String url = 'http://127.0.0.1:8200/v1/planted';

  @override
  String get irreversibleReason => 'it is a probe and is never run against a machine';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async {
    await context.http.send(const HttpRequest('POST', url, body: '{}'));
    return const StepPlan.nothing('would post to the tool');
  }

  @override
  Future<void> apply(StepContext context) async {}
}

/// A step that changes something from the method NOBODY thinks of as running under a dry run.
///
/// The capture is the third thing a dry run drives, and it is the one that is easy to leave out — it
/// exists to prepare an undo, so it does not read as part of the run. This probe is what says the
/// driving is really there: take the capture out of the audit and the test that runs this one
/// WITHOUT the planning ports goes red, because nothing would reach the fake.
final class WritesFromItsCapture extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WritesFromItsCapture();

  /// Where it writes, so a counter-probe can name what got through.
  static const String path = '/etc/planted-by-a-capture';

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(path, before: '', after: 'what this step would write');

  @override
  Future<void> apply(StepContext context) async {}

  /// Reads what was there by writing, which is the shape this probe exists to catch.
  ///
  /// A real one would be subtler — a capture that asks a tool which creates its own state file on
  /// the way to answering — but what has to be shown is that a port refuses whatever the capture
  /// reaches for, and one write shows that as well as a subtle one.
  @override
  Future<bool> capture(StepContext context) async {
    await context.files.write(path, 'written from a capture', mode: 0x180);
    return true;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {}
}

/// A step that runs a command a program row would name, so its answer rests on the row's word.
final class AnswersOnTheRowsWord extends ObservingStep {
  /// Creates the planted step.
  const AnswersOnTheRowsWord();

  @override
  bool get answersOnTrust => true;

  @override
  Future<CheckResult> check(StepContext context) async {
    await context.shell.run(
      const Command.detailed('planted', observes: true, timeout: Duration(seconds: 30)),
    );
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.nothing('would ask what the row names');
}

/// A step that reads the machine and plans, which is what every step is meant to do.
///
/// Reversible, and its capture only reads — so this also says that driving the capture does not
/// report a step which was doing the right thing.
final class OnlyLooks extends ReversibleStep<String?> {
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
  Future<String?> capture(StepContext context) async =>
      await context.files.exists('/etc/planted') ? context.files.read('/etc/planted') : null;

  @override
  Future<void> undo(StepContext context, String? captured) async {}
}
