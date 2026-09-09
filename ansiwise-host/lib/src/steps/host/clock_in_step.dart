library;

import 'package:ansiwise_core/ansiwise_core.dart';

/// What is asked of the time daemon, and asked rather than read out of its configuration: a file
/// says what a machine was TOLD to do, and this step is about what its clock IS.
const Command trackingCommand = Command.observing('chronyc', arguments: <String>['tracking']);

/// The kernel's own verdict. `NTP` is the setting and answers yes on a machine whose every source
/// is unreachable; `NTPSynchronized` is the clock.
const Command synchronisedCommand = Command.observing(
  'timedatectl',
  arguments: <String>['show', '-p', 'NTPSynchronized', '--value'],
);

/// What `chronyc tracking` prints for a reference it does not have.
const String _noReference = '00000000';

/// How far out the clock stands, in seconds, as `chronyc tracking` reports it, or null where that
/// line is absent. Positive is fast and negative is slow: the sign is kept because a clock moved
/// BACKWARDS is the direction that hurts a machine already serving.
double? clockOffsetFrom(String tracking) {
  for (final String line in tracking.split('\n')) {
    if (!line.trimLeft().startsWith('System time')) continue;
    final Match? found = RegExp(r'([0-9]+[.]?[0-9]*)\s+seconds\s+(fast|slow)').firstMatch(line);
    if (found == null) return null;
    final double seconds = double.parse(found.group(1)!);
    return found.group(2) == 'slow' ? -seconds : seconds;
  }
  return null;
}

/// Whether the daemon has a source at all. A machine that reaches none answers with the reference
/// nobody has, and no step can invent a time for it.
bool hasReference(String tracking) {
  for (final String line in tracking.split('\n')) {
    if (!line.trimLeft().startsWith('Reference ID')) continue;
    return !line.contains(_noReference);
  }
  return false;
}

/// Brings the machine's clock into step with a source it can reach, and then measures it.
///
/// **Why a step and not a wait.** Everything installed after this issues or verifies something that
/// carries a time, so a clock that is out has to stop a run. A wait alone only watches: on a machine
/// restored from a snapshot the time daemon is long past the first updates its distribution lets it
/// STEP the clock in, so a large error is slewed instead, at 8.3 per cent — twelve minutes for a
/// minute of error. Measured on a machine on 2026-09-09: 69 seconds out, closing at 91 milliseconds
/// per second, against a window of three minutes. Four runs died in one morning watching that.
///
/// **What it does.** With the kernel synchronised and the error inside the tolerance, nothing. Out
/// of step with a source reachable, it steps the clock and then waits for the kernel's own verdict.
/// With no source reachable it refuses, and names how to see that.
///
/// **Irreversible, and not because of a file.** It writes none. A clock moved backwards on a machine
/// that is already serving cannot be put back: a lease taken out at the old time outlives the new
/// one, and two records written in the same second are written out of order.
final class ClockInStep extends IrreversibleStep {
  /// Admits a clock inside [toleranceSeconds] of its source, steps one outside it, and gives the
  /// kernel [timeoutSeconds] to agree, asked every [intervalSeconds].
  const ClockInStep({
    required this.toleranceSeconds,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// The row as a program file writes it.
  factory ClockInStep.fromArguments(Arguments arguments) => ClockInStep(
    toleranceSeconds: arguments.integer('tolerance_seconds'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What a program file may state about this row.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'tolerance_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 60,
        because:
            'a tolerance under a second is below what a network time source promises, and one over '
            'a minute admits a clock that breaks a freshly issued certificate',
      ),
      describes: 'how far out the clock may stand before this row steps it, in seconds',
      required: false,
      defaultValue: 1,
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 10,
        most: 900,
        because:
            'the kernel takes a few updates to call itself synchronised after a step, and a wait '
            'past a quarter of an hour is a machine nobody is coming back to',
      ),
      describes: 'how long the kernel is given to call itself synchronised, in seconds',
      required: false,
      defaultValue: 180,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 60,
        because:
            'a poll under a second reads the same answer twice, and one over a minute wastes the wait',
      ),
      describes: 'how often the kernel is asked, in seconds',
      required: false,
      defaultValue: 5,
    ),
  ];

  /// How far out the clock may stand before this row steps it, in seconds.
  final int toleranceSeconds;

  /// How long the kernel is given to call itself synchronised, in seconds.
  final int timeoutSeconds;

  /// How often the kernel is asked, in seconds.
  final int intervalSeconds;

  @override
  String get irreversibleReason =>
      'the clock is set, and a clock moved backwards on a machine that is already serving cannot be '
      'put back: a lease taken out at the old time outlives the new one, and two records written in '
      'the same second are written out of order';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await _synchronised(context)) {
      return CheckResult.satisfied(_standing(clockOffsetFrom(await _tracking(context))));
    }
    // A MISSING REFERENCE IS NOT A REFUSAL, and reading it as one is what this row got wrong on the
    // first machine it met. The row that enables the time service stands directly above it in the
    // program, so the service is SECONDS old when this runs, and one that has not completed a
    // measurement reports no reference at all - every source at reach 0, which is a bitmask of the
    // last eight polls and therefore empty however reachable the source is. "Not yet" and "never"
    // are the same reading here, and only the wait below, at the end of its own deadline, has
    // stood long enough to tell them apart.
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      const StepPlan.argv(<String>['chronyc', 'makestep']);

  @override
  Future<void> apply(StepContext context) async {
    final Duration interval = Duration(seconds: intervalSeconds);
    Duration waited = Duration.zero;
    // WHETHER A SOURCE WAS EVER REACHED. It is the whole difference between the two refusals below,
    // and it can only be answered by having waited: see the note in check().
    bool reached = false;
    bool stepped = false;
    while (true) {
      if (await _synchronised(context)) {
        context.log.info(_standing(clockOffsetFrom(await _tracking(context))));
        return;
      }
      final String reading = await _tracking(context);
      if (hasReference(reading)) {
        reached = true;
        // ONE STEP, AND ONLY ONCE A SOURCE IS KNOWN. `chronyc makestep` has nothing to step toward
        // before the first measurement, so a row that stepped before waiting would step nothing and
        // then leave the machine slewing its whole offset for the rest of the deadline - which on a
        // machine a minute out is a deadline it cannot make.
        if (!stepped) {
          stepped = true;
          final double? offset = clockOffsetFrom(reading);
          if (offset != null && offset.abs() > toleranceSeconds) {
            context.log.info(
              '${_away(offset)}, which is past the ${toleranceSeconds}s this row admits - it is '
              'stepped now rather than waited out',
            );
            final CommandResult ran = await context.shell.run(
              const Command.detailed('chronyc', arguments: <String>['makestep'], elevated: true),
            );
            if (!ran.ok) {
              throw CommandFailed(
                argv: <String>['chronyc', 'makestep'],
                exitCode: ran.exitCode,
                stdout: ran.stdout,
                stderr: ran.stderr,
              );
            }
          }
        }
      }
      if (waited.inSeconds >= timeoutSeconds) {
        if (!reached) {
          throw WaitedTooLong(
            waitingFor:
                'a time source this machine can reach - it named none in that whole time, so '
                'nothing here can bring its clock into step; ask it `chronyc sources`, where a '
                'source at reach 0 after this long is one it cannot get to',
            deadline: Duration(seconds: timeoutSeconds),
          );
        }
        final double? last = clockOffsetFrom(await _tracking(context));
        throw WaitedTooLong(
          waitingFor: last == null
              ? 'the kernel to call this clock synchronised'
              : 'the kernel to call this clock synchronised - ${_away(last)}',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      await context.clock.sleep(interval);
      waited += interval;
    }
  }

  String _standing(double? offset) => offset == null
      ? 'the kernel calls this clock synchronised'
      : 'the kernel calls this clock synchronised, ${offset.abs().toStringAsFixed(3)}s from its source';

  String _away(double offset) =>
      'the clock stands ${offset.abs().toStringAsFixed(3)}s '
      '${offset < 0 ? 'behind' : 'ahead of'} its source';

  Future<bool> _synchronised(StepContext context) async {
    final CommandResult asked = await context.shell.run(synchronisedCommand);
    if (!asked.ok) {
      throw CommandFailed(
        argv: synchronisedCommand.argv,
        exitCode: asked.exitCode,
        stdout: asked.stdout,
        stderr: asked.stderr,
      );
    }
    return asked.trimmed == 'yes';
  }

  Future<String> _tracking(StepContext context) async {
    final CommandResult asked = await context.shell.run(trackingCommand);
    if (!asked.ok) {
      throw CommandFailed(
        argv: trackingCommand.argv,
        exitCode: asked.exitCode,
        stdout: asked.stdout,
        stderr: asked.stderr,
      );
    }
    return asked.stdout;
  }
}
