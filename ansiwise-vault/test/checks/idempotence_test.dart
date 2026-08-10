import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

import 'declared_answers.dart';

Future<void> main() async {
  final Idempotence check = Idempotence(
    registry: vaultRegistry,
    answers: answersDeclaredBy(vaultRegistry),
    fixtures: stepFixtures,
  );
  final IdempotenceReading reading = await check.runEveryStep();

  test('every registered step was run twice', () {
    expect(
      reading.coverage,
      hasLength(vaultRegistry.steps.length),
      reason: 'some step was never run, so nothing about its second run was measured',
    );
  });

  test('no registered step was seen to do its work twice', () {
    expect(
      reading.findings,
      isEmpty,
      reason:
          "the shape is exact: the step's check answers Satisfied the second time, before any work, "
          'so the engine never calls apply again',
    );
  });

  test(
    '${reading.notCoveredNames.length} step(s) are NOT COVERED, and they are exactly the ones named '
    'in this file',
    () {
      // A skip is not silent and it is not a pass. Naming them in a ledger the audit asserts against
      // is what makes a step added tomorrow bring its fixture or force somebody to write its name
      // here — and what makes a fixture that stopped working turn the tree red instead of quietly
      // moving one more step into this list.
      expect(
        reading.notCoveredNames,
        orderedEquals(notCoveredByAFakeMachine.toList()..sort()),
        reason:
            'a step a fake machine cannot exercise has not been shown to be idempotent by anything; '
            'either arrange the fake for it in stepFixtures, or name it here',
      );
    },
  );

  group('counter-probe', () {
    // Three steps written here, run through the same machinery. The third is the one this whole
    // audit is shaped around: a step whose work is left behind by a command must come back NOT
    // COVERED and never exercised — because a fake shell answers every command the same way before
    // and after, so its check would answer the same both times for a reason that has nothing to do
    // with the step being idempotent. Collapse the two into one and this is what says so.

    test('a step that would work twice is caught', () async {
      expect(
        await _runTwice(const DoesItsWorkEveryTime()),
        isA<WouldRepeat>(),
        reason: 'a step planted here writes on every run and its check never notices',
      );
    });

    test('a step whose second run is a no-op is exercised', () async {
      expect(
        await _runTwice(const WritesOnlyOnce()),
        isA<Exercised>(),
        reason: 'a step planted here writes once and is satisfied afterwards',
      );
    });

    test('a step the fake machine cannot exercise is not counted as passing', () async {
      expect(
        await _runTwice(const WorksThroughACommand()),
        isA<NotCovered>(),
        reason:
            'a step planted here leaves its postcondition behind with a command the fake shell does '
            'not carry out, and counting that as a pass is the failure this audit exists to prevent',
      );
    });

    test('a fixture that carries the command out makes the same step measurable', () async {
      // The other half of the third: with the fake arranged the way a real machine would be, the
      // same step IS exercised. Without this, an audit that answered NOT COVERED to everything would
      // pass the test above.
      expect(
        await _runTwice(
          const WorksThroughACommand(),
          fixture: (FakeShell shell, FakeFiles files, FakeHttp http) {
            shell.changes('touch ${WorksThroughACommand.path}', () {
              shell.answers('test -e ${WorksThroughACommand.path}', 'there');
            });
          },
        ),
        isA<Exercised>(),
        reason: 'FakeShell.changes is what lets a postcondition actually become true',
      );
    });

    // The shape every step of this package really has: the postcondition is read back over HTTP,
    // and a fake network answers a request without the earlier one having changed what it answers.
    // So such a step must come back NOT COVERED, and never exercised.
    test('a step whose work goes over HTTP is not counted as passing', () async {
      expect(
        await _runTwice(const WorksThroughARequest()),
        isA<NotCovered>(),
        reason:
            'a step planted here leaves its postcondition behind with a POST the fake network does '
            'not carry out, and counting that as a pass is what would make this whole package look '
            'proven',
      );
    });
  });
}

Future<Coverage> _runTwice(Step step, {Fixture? fixture}) =>
    runTwice(const StepName('planted'), step, Arguments.none, fixture: fixture);

/// The fake machine each named step meets, by the name a program file writes.
///
/// Empty, and that is a statement rather than an omission: every step of this package reaches its
/// tool over HTTP, and `FakeHttp` answers a request without a request before it having changed what
/// it answers — there is no arrangement of it under which a POST makes the following GET report the
/// new state. So no fixture here could take a step out of the ledger below, and every one of them
/// stands in it as unproven.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// Where the planted steps write, so they cannot read each other's file.
const String _plantedPath = '/etc/planted';

/// A step that writes every time it is run and never notices that it has.
final class DoesItsWorkEveryTime extends ReversibleStep<bool> {
  /// Creates the planted step.
  const DoesItsWorkEveryTime();

  @override
  Future<CheckResult> check(StepContext context) async => const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'again');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'again', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step that writes once and answers satisfied from then on.
final class WritesOnlyOnce extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WritesOnlyOnce();

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(_plantedPath)) {
      return const CheckResult.ready();
    }
    return await context.files.read(_plantedPath) == 'once'
        ? const CheckResult.satisfied('the file already holds what this step writes')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.diff(_plantedPath, before: '', after: 'once');

  @override
  Future<void> apply(StepContext context) async =>
      context.files.write(_plantedPath, 'once', mode: 0x180);

  @override
  Future<bool> capture(StepContext context) => context.files.exists(_plantedPath);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (!captured) {
      await context.files.delete(_plantedPath);
    }
  }
}

/// A step whose postcondition a real command would leave behind, and a fake one never does.
final class WorksThroughACommand extends ReversibleStep<bool> {
  /// Creates the planted step.
  const WorksThroughACommand();

  /// The marker the command leaves behind.
  static const String path = '/etc/planted-by-a-command';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there'
        ? const CheckResult.satisfied('the marker is there')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(<String>['touch', path]);

  @override
  Future<void> apply(StepContext context) async {
    await context.shell.run(const Command('touch', <String>[path]));
  }

  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult marker = await context.shell.run(
      const Command.observing('test', <String>['-e', path]),
    );
    return marker.trimmed == 'there';
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(const Command('rm', <String>['-f', path]));
  }
}

/// A step whose postcondition a real request would leave behind, and a fake one never does.
final class WorksThroughARequest extends IrreversibleStep {
  /// Creates the planted step.
  const WorksThroughARequest();

  /// Where it reads and writes, so the two requests are about one thing.
  static const String url = 'http://127.0.0.1:8200/v1/planted';

  @override
  String get irreversibleReason =>
      'what stood under that key before is overwritten and is held nowhere else';

  @override
  Future<CheckResult> check(StepContext context) async {
    final HttpAnswer found = await context.http.send(const HttpRequest('GET', url));
    return found.body == 'there'
        ? const CheckResult.satisfied('the entry is there')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.nothing('would post the entry');

  @override
  Future<void> apply(StepContext context) async {
    await context.http.send(const HttpRequest('POST', url, body: '{}'));
  }
}

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// Every step of this package reaches its tool over HTTP: it asks what the tool holds, and it posts
/// what the tool should hold. `FakeHttp` records a request and answers from a fixed table, so a POST
/// does not change what the GET after it reports, and the second check reads exactly what the first
/// one did. That is not a defect in the step, and it is not evidence that the step is idempotent —
/// so all of them stand here, and this whole package's idempotence rests on the tests beside this
/// directory rather than on this audit.
///
/// A name leaves this list on the day a fake network can be arranged to answer differently after a
/// request that changed something, the way `FakeShell.changes` already does for a command.
const Set<String> notCoveredByAFakeMachine = <String>{
  'vault_auth_method',
  'vault_auth_role',
  'vault_init',
  'vault_kv_entry',
  'vault_kv_mount',
  'vault_policy',
  'vault_unsealed',
};
