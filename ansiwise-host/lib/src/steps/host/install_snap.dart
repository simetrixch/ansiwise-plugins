import 'package:ansiwise_core/ansiwise_core.dart';

import 'on_the_path.dart';

/// Puts a snap on the machine, switched on and tracking the channel a program pins it to.
///
/// **One capability and not three, because three starting points reach one end state.** A machine is
/// found with no such snap at all, with the snap installed on another channel, or with it installed
/// and switched off. Two measurements tell those apart — whether the snap's command is on the path,
/// and what `snap list` says the snap tracks — and this step's check makes them. That is what lets a
/// program say WHAT the machine is to carry instead of naming which of three commands to run at it.
///
/// **A snap that is installed but switched off is invisible to the path and visible to snapd, and
/// that pair is what this step is built around.** `snap disable` leaves the snap installed and only removes its
/// entries from `/snap/bin`, so a presence test built on the path finds nothing and concludes the
/// machine is clean — while `snap install` refuses the very same snap as already installed and the
/// run dies there. The tracked channel is what tells the two states apart, and switching the snap
/// back on is what this does about it.
///
/// **Switching it on is deliberately not an install.** The snap on the machine carries its own data
/// directory and everything it has written into it, and installing over that would be a different
/// and much larger act than the one the machine needs.
///
/// **The channel comparison is what keeps this from failing on a machine that is already right.** A
/// plain `snap refresh` with nothing to update exits non-zero, so a step that refreshed
/// unconditionally would report a failure on every converged machine. A channel SWITCH is a real
/// refresh and never reaches that exit, which is why the comparison comes first and the command
/// second.
///
/// **It cannot be taken back although one of its three paths could be.** Switching a snap back on
/// could be undone by switching it off again; installing one, and moving one onto another channel,
/// could not — and which path a run takes is decided by the machine it finds, not by the program. A
/// step declares one kind for every machine, so it declares the kind that holds for the worst of
/// them. The cost is that a run which only switched a snap on is announced as a point of no return
/// it was not; the other way round would be a step promising an undo it cannot perform, which is the
/// failure that matters.
final class InstallSnap extends IrreversibleStep {
  /// Puts [snap] on the machine at [channel].
  const InstallSnap({required this.snap, required this.channel, required this.classic});

  /// Builds the step from what the program gave it.
  factory InstallSnap.fromArguments(Arguments arguments) => InstallSnap(
    snap: arguments.text('snap'),
    channel: arguments.text('channel'),
    classic: arguments.flag('classic'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'snap',
      kind: ArgumentKind.text,
      describes: 'the snap this machine carries, by the name it is published under',
    ),
    ArgumentSpec(
      name: 'channel',
      kind: ArgumentKind.text,
      describes: 'the snap channel the program pins',
    ),
    ArgumentSpec(
      name: 'classic',
      kind: ArgumentKind.flag,
      describes:
          'whether this snap is installed with classic confinement, which snapd refuses for a '
          'snap that does not ask for it and demands for one that does',
      required: false,
      defaultValue: false,
    ),
  ];

  /// Whether the command [snap] puts on the path is there.
  ///
  /// The name a snap is published under is the name snapd links into `/snap/bin` for its command,
  /// which is what lets one question answer for the other. It is the only question a bare presence
  /// test can answer, and on its own it is not enough: a disabled snap is installed and off the path
  /// at the same time. [trackedChannel] is what tells the two apart.
  static Future<bool> onPath(StepContext context, String snap) async {
    final CommandResult answer = await context.shell.run(onThePath(snap));
    return foundOnThePath(answer);
  }

  /// The channel [snap] tracks, null when no such snap is installed, or why neither could be read.
  ///
  /// Read out of the fourth column of `snap list`, which snapd fills whether the snap is enabled or
  /// disabled. A non-empty answer with nothing on the path is exactly the disabled snap.
  ///
  /// **`snap list <name>` EXITS NON-ZERO FOR TWO DIFFERENT MACHINES**, and read as one of them the
  /// other was reported as a machine carrying no such snap: a snap that is genuinely not installed,
  /// and a snapd that could not be asked at all. The second matters most where the snap is DISABLED,
  /// because such a snap is off the path as well, so the presence test beside this one cannot stand
  /// in for it — and the step that TAKES A SNAP AWAY read the pair as "there is none to remove".
  ///
  /// `snap version` is what tells them apart, and it is asked only where the first reading failed:
  /// it reports the daemon's own version and answers whenever snapd is reachable, so a `snap list`
  /// that failed while `snap version` answers really is a machine without that snap.
  static Future<({String? channel, String? refusal})> trackedChannel(
    StepContext context,
    String snap,
  ) async {
    final CommandResult listed = await context.shell.run(
      Command.observing('snap', arguments: <String>['list', snap]),
    );
    if (!listed.ok) {
      final CommandResult snapd = await context.shell.run(
        const Command.observing('snap', arguments: <String>['version']),
      );
      if (!snapd.ok) {
        return (
          channel: null,
          refusal:
              'snapd would not say whether $snap is installed, so nothing here knows whether it is: '
              '"snap list $snap" answered ${listed.exitCode} and "snap version" answered '
              '${snapd.exitCode}'
              '${snapd.stderr.trim().isEmpty ? '' : ' — ${snapd.stderr.trim()}'}',
        );
      }
      return (channel: null, refusal: null);
    }
    for (final String line in listed.stdout.split('\n')) {
      final List<String> columns = line.trim().split(RegExp(r'\s+'));
      if (columns.length >= 4 && columns.first == snap) {
        return (channel: columns[3], refusal: null);
      }
    }
    return (channel: null, refusal: null);
  }

  /// The snap, by the name it is published under.
  final String snap;

  /// The channel the snap is pinned to.
  final String channel;

  /// Whether the snap is installed with classic confinement.
  final bool classic;

  @override
  String get irreversibleReason =>
      'a machine that did not carry $snap now carries it, and the way back is a removal that takes '
      'the snap and everything it kept in its own data directory together, with nothing on the '
      'machine holding a copy — and a snap moved onto another channel cannot be moved back at all, '
      'because snapd keeps no note of the channel it left';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? channel, String? refusal}) reading = await trackedChannel(context, snap);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? tracked = reading.channel;
    if (tracked == null) {
      if (await onPath(context, snap)) {
        return CheckResult.blocked(
          '$snap answers on the path and "snap list $snap" names no channel for it, so nothing on '
          'this machine says what it tracks — and a channel that cannot be read cannot be shown to '
          'be $channel',
        );
      }
      return const CheckResult.ready();
    }
    if (tracked == channel && await onPath(context, snap)) {
      return CheckResult.satisfied('$snap is installed, switched on and tracks $channel');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // The command the state found calls for. A snap that is switched off AND on another channel
    // takes two, and a plan carries one — so what is shown is the one that runs first, and the
    // channel move behind it is reported when it runs.
    final ({String? channel, String? refusal}) reading = await trackedChannel(context, snap);
    if (reading.refusal case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    if (reading.channel == null) {
      return StepPlan.argv(_install);
    }
    if (!await onPath(context, snap)) {
      return StepPlan.argv(_enable);
    }
    return StepPlan.argv(_refresh);
  }

  @override
  Future<void> apply(StepContext context) async {
    final ({String? channel, String? refusal}) reading = await trackedChannel(context, snap);
    if (reading.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String? tracked = reading.channel;
    if (tracked == null) {
      context.log.info('installing the $snap snap from $channel');
      await _mustRun(context, _install);
      return;
    }
    if (!await onPath(context, snap)) {
      context.log.info('a $snap snap is installed and switched off — switching it back on');
      await _mustRun(context, _enable);
    }
    if (tracked != channel) {
      context.log.info('moving the $snap snap from $tracked onto $channel');
      await _mustRun(context, _refresh);
    }
  }

  List<String> get _install => <String>[
    'snap',
    'install',
    snap,
    if (classic) '--classic',
    '--channel=$channel',
  ];

  List<String> get _enable => <String>['snap', 'enable', snap];

  List<String> get _refresh => <String>['snap', 'refresh', snap, '--channel=$channel'];

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
