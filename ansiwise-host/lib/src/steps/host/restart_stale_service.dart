import 'package:ansiwise_core/ansiwise_core.dart';

/// Brings a service onto the executable that stands on disk, where it is still running an older one.
///
/// **A SERVICE DOES NOT NOTICE THAT ITS BINARY WAS REPLACED.** Replacing an executable is a rename:
/// the directory entry points at a new file and every later invocation gets it, while a process
/// that is already running keeps the inode it started from — which is exactly what makes the
/// replacement safe. It also means the service goes on serving the OLD code, indefinitely, while
/// the file on disk answers the new version and everything that reads the disk is satisfied.
///
/// That is the shape this step exists for: a machine that reports itself at the pin and is not.
///
/// **THE QUESTION IS ASKED OF THE KERNEL AND NOT OF A CLOCK.** `/proc/<pid>/exe` is a link to the
/// inode a process is executing, and where that inode no longer has a name the kernel renders it as
/// `<path> (deleted)`. So a service running a replaced binary SAYS SO, exactly, with no timestamps
/// compared and no arithmetic between a file's modification time and a process's start.
///
/// A comparison of times would have to reconcile a monotonic clock the service manager reports
/// against a wall clock the filesystem records, and answer wrongly the first time either moved.
/// This asks the one question that has a definite answer.
///
/// **IT DOES NOT START WHAT IS NOT RUNNING.** A unit that is loaded and inactive is left alone and
/// said so: something stopped it, and a step whose name is about staleness restarting it would be
/// deciding a thing nobody asked it to decide. A unit the service manager does not know at all is a
/// REFUSAL naming it — restarting nothing is not restarting, and a row pointing at a unit that is
/// not there is a row that will never do what it says.
final class RestartStaleService extends IrreversibleStep {
  /// Restarts [unit] where the service is running an executable that has been replaced.
  const RestartStaleService({required this.unit});

  /// Builds the step from what the program gave it.
  factory RestartStaleService.fromArguments(Arguments arguments) =>
      RestartStaleService(unit: arguments.text('unit'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'unit',
      kind: ArgumentKind.text,
      describes:
          'the unit the service manager knows the service by, such as ansiwise.service — the step '
          'asks that manager about it and never guesses a name from a tool',
    ),
  ];

  /// The unit the service manager knows the service by.
  final String unit;

  @override
  String get irreversibleReason =>
      'the service is stopped and started again. Whatever it was in the middle of is not resumed, '
      'and every connection it was serving is ended — nothing here keeps a record of either';

  @override
  Future<CheckResult> check(StepContext context) async {
    final _Service service = await _read(context);
    if (service.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (!service.active) {
      return CheckResult.satisfied(
        '$unit is loaded and not running, so it is running no old executable. Something stopped '
        'it, and starting it again is not what this row is for',
      );
    }
    if (!service.stale) {
      return CheckResult.satisfied('$unit is running the executable that stands on disk');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final _Service service = await _read(context);
    if (service.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.argv(<String>['systemctl', 'restart', unit]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult restarted = await context.shell.run(
      Command.detailed('systemctl', arguments: <String>['restart', unit], elevated: true),
    );
    if (!restarted.ok) {
      throw CommandFailed(
        argv: <String>['systemctl', 'restart', unit],
        exitCode: restarted.exitCode,
        stdout: restarted.stdout,
        stderr: restarted.stderr,
      );
    }
    // THE VERDICT IS READ OFF THE SERVICE MANAGER, never off the exit code of the restart. A
    // restart that returns zero and a service that came back up are two different facts: a unit
    // whose executable is missing, or whose new one refuses its own configuration, is restarted
    // successfully and is down a second later.
    final _Service after = await _read(context);
    if (after.refusal case final String refusal) {
      throw StateError('$unit was restarted and then could not be read at all: $refusal');
    }
    if (!after.active) {
      throw StateError(
        '$unit was restarted and is not running. The restart itself reported no failure, so what '
        'is wrong is in the service and not in the restarting — read what the service manager says '
        'about it',
      );
    }
    if (after.stale) {
      throw StateError(
        '$unit was restarted and is STILL running a replaced executable. A restart that leaves the '
        'old inode running is a unit that did not actually stop — a lingering process it does not '
        'account for, or a manager configured to keep one',
      );
    }
  }

  /// What the service manager and the kernel say about this unit.
  Future<_Service> _read(StepContext context) async {
    final CommandResult shown = await context.shell.run(
      Command.observing(
        'systemctl',
        arguments: <String>['show', '-p', 'LoadState', '-p', 'ActiveState', '-p', 'MainPID', unit],
      ),
    );
    if (!shown.ok) {
      return _Service.unreadable(
        'the service manager would not say anything about $unit: ${shown.stderr.trim()}',
      );
    }
    final Map<String, String> said = <String, String>{
      for (final String line in shown.stdout.split('\n'))
        if (line.contains('=')) line.split('=').first.trim(): line.split('=').last.trim(),
    };
    if (said['LoadState'] != 'loaded') {
      return _Service.unreadable(
        'the service manager does not know a unit called $unit — it says LoadState is '
        '"${said['LoadState'] ?? 'nothing at all'}". Restarting nothing is not restarting, so this '
        'is refused rather than passed over',
      );
    }
    if (said['ActiveState'] != 'active') {
      return const _Service.of(active: false, stale: false);
    }
    final String pid = said['MainPID'] ?? '0';
    if (pid == '0' || pid.isEmpty) {
      return _Service.unreadable(
        '$unit is active and the service manager names no main process for it, so there is nothing '
        'to ask which executable is running',
      );
    }
    // The kernel renders the link as `<path> (deleted)` where the inode a process is executing no
    // longer has a name — which is precisely what replacing a binary under a running service does.
    final CommandResult running = await context.shell.run(
      Command.observing('readlink', arguments: <String>['/proc/$pid/exe'], elevated: true),
    );
    if (!running.ok) {
      return _Service.unreadable(
        'what executable process $pid of $unit is running could not be read: '
        '${running.stderr.trim()}',
      );
    }
    return _Service.of(active: true, stale: running.trimmed.endsWith(deletedMarker));
  }

  /// What the kernel appends to a link whose inode no longer has a name.
  static const String deletedMarker = '(deleted)';
}

/// What the service manager and the kernel say, or why they could not be asked.
final class _Service {
  const _Service.of({required this.active, required this.stale}) : refusal = null;

  const _Service.unreadable(String this.refusal) : active = false, stale = false;

  /// Whether the service manager reports the unit as running.
  final bool active;

  /// Whether the running process is executing an inode that no longer has a name.
  final bool stale;

  /// Why nothing could be read, or null when it could.
  final String? refusal;
}
