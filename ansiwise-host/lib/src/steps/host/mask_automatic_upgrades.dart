import 'package:ansiwise_core/ansiwise_core.dart';

/// Takes the distribution's automatic package upgrades off a machine an installation is about to
/// own, after a run already under way has been waited out.
///
/// **THE INSTALLATION OWNS THE PACKAGE MANAGER.** The program this row opens installs, removes and
/// cleans packages itself, and everything after it stands on the service manager. A second party
/// upgrading packages beside it is not a nuisance but a fault: an upgrade of the service manager's
/// own package re-executes PID 1, and a `snap run` that asks PID 1 for its transient scope in that
/// instant is answered with a closed bus — the command exits 46 without having run, and the step
/// that issued it reads a machine it cannot see. That is what ended a cluster installation at the
/// step that reapplies its network manifest (#185), and it is the same fault at every later moment
/// of the machine's life, so the timers are masked for good and not paused for the run.
///
/// **WAITED OUT, NEVER KILLED.** A run of the upgrade already in progress is left to finish: a
/// package manager interrupted between unpack and configure leaves a machine no later step can
/// reason about. The timers are masked only once no upgrade service is active — and a one-shot
/// service reports `activating` for the whole of its run, so that word counts as running here.
///
/// **MASKED, NOT DISABLED.** A disabled timer is started again by the next package that lists it in
/// its `postinst`, and the upgrade package itself does. A mask is a unit the manager refuses to
/// start whoever asks.
///
/// **THE POSTCONDITION IS THE MANAGER'S WORD.** `UnitFileState=masked` on every timer and no
/// service running is what this step produces, and it is read back after the commands rather than
/// inferred from their exit codes.
final class MaskAutomaticUpgrades extends ReversibleStep<List<String>> {
  /// Masks [timers] once none of [services] runs, giving them [timeoutSeconds] to finish, asked
  /// every [intervalSeconds].
  const MaskAutomaticUpgrades({
    required this.timers,
    required this.services,
    required this.timeoutSeconds,
    required this.intervalSeconds,
  });

  /// The row as a program file writes it.
  factory MaskAutomaticUpgrades.fromArguments(Arguments arguments) => MaskAutomaticUpgrades(
    timers: arguments.textList('timers'),
    services: arguments.textList('services'),
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
  );

  /// What a program file may state about this row.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'timers',
      kind: ArgumentKind.textList,
      describes: 'the timers that start automatic upgrades, which this row masks',
      required: false,
      defaultValue: <String>['apt-daily.timer', 'apt-daily-upgrade.timer'],
    ),
    ArgumentSpec(
      name: 'services',
      kind: ArgumentKind.textList,
      describes: 'the services those timers start, which this row waits out before it masks',
      required: false,
      defaultValue: <String>['apt-daily.service', 'apt-daily-upgrade.service'],
    ),
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 10,
        most: 3600,
        because:
            'an upgrade of a snapshot weeks old takes minutes, and one still running after an hour '
            'is a machine somebody has to look at',
      ),
      describes: 'how long a running upgrade is given to finish, in seconds',
      required: false,
      defaultValue: 1200,
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
      describes: 'how often the service manager is asked, in seconds',
      required: false,
      defaultValue: 5,
    ),
  ];

  /// The timers that start automatic upgrades.
  final List<String> timers;

  /// The services those timers start.
  final List<String> services;

  /// How long a running upgrade is given to finish, in seconds.
  final int timeoutSeconds;

  /// How often the service manager is asked, in seconds.
  final int intervalSeconds;

  /// What the manager is asked about a unit, in the order it answers.
  static const List<String> properties = <String>['LoadState', 'UnitFileState', 'ActiveState'];

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Reading reading = await _read(context);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return reading.settled
        ? CheckResult.satisfied(
            '${timers.join(' and ')} are masked and no upgrade service is running',
          )
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['systemctl', 'mask', '--now', ...timers]);

  @override
  Future<void> apply(StepContext context) async {
    final Duration interval = Duration(seconds: intervalSeconds);
    Duration waited = Duration.zero;
    while (true) {
      final _Reading reading = await _read(context);
      if (reading.refusal case final String refusal) {
        throw StateError(refusal);
      }
      if (reading.running.isEmpty) {
        break;
      }
      if (waited.inSeconds >= timeoutSeconds) {
        throw WaitedTooLong(
          waitingFor:
              '${reading.running.join(' and ')} to finish - an upgrade that long is one to look at '
              'on the machine, under `journalctl -u ${reading.running.first}`',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      context.log.info('${reading.running.join(' and ')} running - waited out, never killed');
      await context.clock.sleep(interval);
      waited += interval;
    }

    for (final String timer in timers) {
      await _mustRun(context, <String>['systemctl', 'mask', '--now', timer]);
    }

    final _Reading after = await _read(context);
    if (after.refusal case final String refusal) {
      throw StateError('the timers were masked and then could not be read at all: $refusal');
    }
    if (after.settled) {
      return;
    }
    throw StateError(
      'the timers were masked and the service manager reports ${after.answer}. The commands '
      'themselves reported no failure, so a unit the manager still calls something other than '
      'masked is one it loads from somewhere a mask does not cover',
    );
  }

  /// Which timers were already masked before this run, so the undo leaves those as it found them.
  @override
  Future<List<String>> capture(StepContext context) async {
    final _Reading before = await _read(context);
    return <String>[
      for (final String timer in timers)
        if (before.masked(timer)) timer,
    ];
  }

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    for (final String timer in timers) {
      if (captured.contains(timer)) {
        continue;
      }
      await context.shell.run(
        Command.detailed('systemctl', arguments: <String>['unmask', timer], elevated: true),
      );
      await context.shell.run(
        Command.detailed('systemctl', arguments: <String>['start', timer], elevated: true),
      );
    }
  }

  /// What the service manager says about every timer and every service.
  Future<_Reading> _read(StepContext context) async {
    final Map<String, Map<String, String>> said = <String, Map<String, String>>{};
    for (final String unit in <String>[...timers, ...services]) {
      final List<String> asked = <String>[
        for (final String property in properties) ...<String>['-p', property],
      ];
      final CommandResult shown = await context.shell.run(
        Command.observing('systemctl', arguments: <String>['show', ...asked, unit]),
      );
      if (!shown.ok) {
        return _Reading.unreadable(
          'the service manager would not say anything about $unit: ${shown.stderr.trim()}',
        );
      }
      final Map<String, String> answers = <String, String>{};
      for (final String line in shown.stdout.split('\n')) {
        final int cut = line.indexOf('=');
        if (cut > 0) {
          answers[line.substring(0, cut).trim()] = line.substring(cut + 1).trim();
        }
      }
      said[unit] = answers;
    }
    return _Reading.of(said, timers: timers, services: services);
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
    }
  }
}

/// What the service manager says about the timers and the services, or why it could not be asked.
final class _Reading {
  const _Reading.of(this.said, {required this.timers, required this.services}) : refusal = null;

  const _Reading.unreadable(String this.refusal)
    : said = const <String, Map<String, String>>{},
      timers = const <String>[],
      services = const <String>[];

  /// What the manager answered, unit by unit and property by property.
  final Map<String, Map<String, String>> said;

  /// Why nothing could be read, or null when it could.
  final String? refusal;

  final List<String> timers;
  final List<String> services;

  /// Whether the manager refuses to start [timer] whoever asks.
  bool masked(String timer) => said[timer]?['UnitFileState'] == 'masked';

  /// Whether [unit] is doing anything right now — and a one-shot service spends its whole run in
  /// `activating`, so that is running too.
  bool isRunning(String unit) => switch (said[unit]?['ActiveState']) {
    'active' || 'activating' || 'reloading' || 'deactivating' => true,
    _ => false,
  };

  /// The services still running.
  List<String> get running => <String>[
    for (final String service in services)
      if (isRunning(service)) service,
  ];

  /// Whether all of it holds at once, which is the state the step produces.
  bool get settled =>
      timers.every((String timer) => masked(timer) && !isRunning(timer)) && running.isEmpty;

  /// Everything the manager answered, as one line an operator can act on.
  String get answer => <String>[
    for (final MapEntry<String, Map<String, String>> unit in said.entries)
      '${unit.key}: ${<String>[for (final String property in MaskAutomaticUpgrades.properties) '$property=${unit.value[property] ?? 'nothing'}'].join(', ')}',
  ].join('; ');
}
