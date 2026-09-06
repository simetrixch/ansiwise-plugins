import 'package:ansiwise_core/ansiwise_core.dart';

/// Hands a unit file to the service manager, so the service runs now and again at every boot.
///
/// **A UNIT FILE IS NOT A SERVICE.** A file written into the manager's directory is read by nothing:
/// the manager loads that directory at start-up and when it is told to, it starts nothing it was not
/// told to want, and a machine coming back from a restart comes back without it. Three things turn
/// the file into a service and this step does all three — the manager is told to read the directory
/// again, the unit is wanted by the target the manager reaches on its way up, and it is run once
/// here.
///
/// **RUNNING IT HERE IS WHAT PROVES THE FILE.** A unit installed and never started is a command line
/// nobody has executed, and the first execution then happens at a restart nobody is watching. The
/// restart at the end of [apply] makes the run that proves the unit the run of the file that stands
/// on disk right now, and its outcome is read back before this step reports anything.
///
/// **RESTARTED AND NOT STARTED.** A unit that already reports itself as having succeeded is not
/// started again, so `start` on a rewritten unit leaves the new command line standing unexecuted
/// until the machine is next restarted.
///
/// **THE MANAGER IS ASKED WHETHER IT HAS READ THE FILE THAT STANDS ON DISK.** `NeedDaemonReload` is
/// its own answer to exactly that, so a unit whose text was rewritten after the manager loaded it is
/// found here rather than by an operator wondering why an edited unit behaves the old way. Nothing
/// compares timestamps: a file's modification time and a manager's start time are read off two
/// different clocks.
///
/// **AND SO IS EVERY UNIT THIS ONE STARTS.** A timer whose own file did not change answers
/// `NeedDaemonReload=no` while the service it fires was rewritten under it, and a step reading only
/// the unit it was named finds nothing to do and leaves the manager holding the old service. The
/// manager names what a unit starts itself, under `Triggers`, so nothing here derives a service name
/// from a timer's — and the same property answers for a socket and a path unit. One level, because
/// what a timer starts is a service and a service starts nothing.
///
/// **THE UNIT HAS TO BE ONE THAT STAYS ACTIVE** — an ordinary service, or a one-shot carrying
/// `RemainAfterExit=yes`. What this step reports is what the manager says, and the manager says
/// `inactive` both for a one-shot that finished successfully and for a unit that has never run at
/// all. Those two are the same word and this step will not tell an operator they are the same state,
/// so a one-shot without that line is refused by the postcondition rather than passed.
final class EnableService extends ReversibleStep<bool> {
  /// Hands [unit] to the service manager.
  const EnableService({required this.unit});

  /// Builds the step from what the program gave it.
  factory EnableService.fromArguments(Arguments arguments) =>
      EnableService(unit: arguments.text('unit'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default. Which unit a machine is to carry is the caller's own, and a default here would be
    // this package naming one product's service for every product that ever calls the step.
    ArgumentSpec(
      name: 'unit',
      kind: ArgumentKind.text,
      describes:
          'the unit the service manager knows the service by, base name and suffix, as the file '
          'under its unit directory is called. It has to be a unit that stays active once it has '
          'run — an ordinary service, or a one-shot carrying RemainAfterExit=yes — because a '
          'one-shot without that line is reported as inactive both when it has finished and when '
          'it has never run',
    ),
  ];

  /// The unit the service manager knows the service by.
  final String unit;

  /// What the manager is asked about the unit, in the order it answers.
  static const List<String> properties = <String>[
    'LoadState',
    'UnitFileState',
    'ActiveState',
    'NeedDaemonReload',
    'Triggers',
  ];

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Unit state = await _read(context);
    if (state.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    return state.settled
        ? CheckResult.satisfied(
            '$unit is enabled, running, and the manager has read the unit file that stands on disk',
          )
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['systemctl', 'enable', '--now', unit]);

  @override
  Future<void> apply(StepContext context) async {
    // THE DIRECTORY IS READ AGAIN FIRST, and the two commands below are about a unit the manager
    // would otherwise not know exists: a unit file an earlier row of the same run wrote is a file
    // the manager has not seen, and one whose text was rewritten is a file it has seen an older
    // version of.
    await _mustRun(context, <String>['systemctl', 'daemon-reload']);
    await _mustRun(context, <String>['systemctl', 'enable', unit]);
    await _mustRun(context, <String>['systemctl', 'restart', unit]);

    final _Unit after = await _read(context);
    if (after.refusal case final String refusal) {
      throw StateError('$unit was enabled and then could not be read at all: $refusal');
    }
    if (after.settled) {
      return;
    }
    throw StateError(
      '$unit was enabled and restarted, and the service manager reports ${after.answer}. The '
      'commands themselves reported no failure, so what is wrong is in a unit and not in the '
      'enabling. A unit the manager does not find is one whose file is not in the directory it '
      'reads; a unit that ran and finished is reported inactive unless it carries '
      'RemainAfterExit=yes, and this step cannot tell that apart from one that never ran',
    );
  }

  /// Whether the manager already started this unit at boot before the run.
  ///
  /// A machine can arrive with the unit enabled, and taking this run back is not a licence to stop
  /// a service this run did not install. Only a unit this run enabled is disabled again.
  ///
  /// What this unit starts is not asked about, because the undo below touches only this one.
  @override
  Future<bool> capture(StepContext context) async => (await _show(context, unit)).enabled;

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command.detailed('systemctl', arguments: <String>['disable', '--now', unit], elevated: true),
    );
  }

  /// What the service manager says about this unit and about every unit this one starts.
  ///
  /// A unit it starts is asked ONE question, whether the manager has read the file that stands on
  /// disk. A service a timer fires is neither wanted at boot nor running between firings, so the
  /// other answers about it describe a healthy machine and would refuse every one of them.
  Future<_Unit> _read(StepContext context) async {
    final _Unit state = await _show(context, unit);
    if (state.refusal != null) {
      return state;
    }
    for (final String started in state.triggers) {
      final _Unit downstream = await _show(context, started);
      if (downstream.refusal case final String refusal) {
        return _Unit.unreadable(refusal);
      }
      if (downstream.reloadNeeded) {
        return _Unit.of(state.said, stale: started);
      }
    }
    return state;
  }

  /// What the service manager says about [named].
  Future<_Unit> _show(StepContext context, String named) async {
    final List<String> asked = <String>[
      for (final String property in properties) ...<String>['-p', property],
    ];
    final CommandResult shown = await context.shell.run(
      Command.observing('systemctl', arguments: <String>['show', ...asked, named]),
    );
    if (!shown.ok) {
      return _Unit.unreadable(
        'the service manager would not say anything about $named: ${shown.stderr.trim()}',
      );
    }
    final Map<String, String> said = <String, String>{};
    for (final String line in shown.stdout.split('\n')) {
      final int cut = line.indexOf('=');
      if (cut > 0) {
        said[line.substring(0, cut).trim()] = line.substring(cut + 1).trim();
      }
    }
    return _Unit.of(said);
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

/// What the service manager says about one unit, or why it could not be asked.
final class _Unit {
  /// Records what the manager answered, keyed by the property it was asked for.
  const _Unit.of(this.said, {this.stale}) : refusal = null;

  /// Records that nothing could be read, because [refusal].
  const _Unit.unreadable(String this.refusal) : said = const <String, String>{}, stale = null;

  /// What the manager answered, property by property.
  final Map<String, String> said;

  /// Why nothing could be read, or null when it could.
  final String? refusal;

  /// A unit this one starts whose file the manager has not read, or null where there is none.
  final String? stale;

  /// Everything the manager answered, as one line an operator can act on.
  ///
  /// Every property that was asked for, including the ones no decision here rests on: which of them
  /// explains a unit that did not come up is not knowable in advance, and a message naming only the
  /// three this step weighs sends the reader back to the machine to ask the fourth.
  String get answer => <String>[
    for (final String property in EnableService.properties)
      '$property=${said[property] ?? 'nothing'}',
    if (stale case final String started)
      'and it starts $started, which the manager has not re-read',
  ].join(', ');

  /// Whether the manager starts this unit on its way up.
  bool get enabled => said['UnitFileState'] == 'enabled';

  /// Whether the unit is running, which for a one-shot carrying `RemainAfterExit=yes` is the state
  /// it holds after its command succeeded.
  bool get active => said['ActiveState'] == 'active';

  /// Whether the unit file on disk has moved on from what the manager loaded.
  ///
  /// A manager that said nothing is not one that said no. The property stands on every unit the
  /// manager knows, including one whose file it cannot find, so its absence is a reading that did
  /// not happen and reading it as `no` would pass a unit nobody measured.
  bool get reloadNeeded => said['NeedDaemonReload'] != 'no';

  /// The units this one starts, which the manager names rather than this step deriving them.
  Iterable<String> get triggers =>
      (said['Triggers'] ?? '').split(' ').where((String named) => named.isNotEmpty);

  /// Whether all of it holds at once, which is the state this step produces.
  bool get settled => enabled && active && !reloadNeeded && stale == null;
}
