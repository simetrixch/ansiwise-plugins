import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';
import 'reapply_calico_manifest.dart';

/// Holds the network agent's masquerade to the source ports this machine opens its own connections
/// from.
///
/// **The defect this exists against, measured end to end.** The agent masquerades the pod network
/// behind the machine's address and, left alone, picks the source port of a rewritten connection out
/// of the whole port space — its rule carries the fully random spread and no range. The network the
/// machine hangs on may only carry the answer back for the ports the MACHINE is known to open, and
/// then every rewritten connection given a port outside that range is never answered. Nothing reads
/// as a network fault: about half of what leaves a pod times out, images fail to pull naming no
/// cause, a public repository cannot be listed, and the same connection from the machine itself
/// works every time. Measured on one machine: from a pod, 11 of 20 connections to a public address
/// on 443 were answered and from the machine 20 of 20 were; the answered source ports were all at or
/// above the low end of the machine's own range and the unanswered ones all below it; and a plain
/// socket ON THE MACHINE, bound to a low source port, was not answered either — so what discards the
/// answer is upstream of the machine, and nothing on the machine could have been configured to fix
/// it.
///
/// **The rule this writes down is the general one and not that network's.** Pods masquerade into the
/// same source ports the machine itself uses, so whatever path works for the machine works for them.
/// That is measured from the machine — no range is written down here, and a machine whose kernel is
/// tuned differently hands its own range on — which is why this is not a step for one hosting
/// provider.
///
/// **What this machine's range is is not read here.** It arrives as [portRange] from the row that
/// measured it. Reading the machine again in this package would be a second answer to one question,
/// and two answers can disagree with nothing to report it.
///
/// **Two places carry the range, and only one of them is this step's.** The agent's settings object
/// holds it at [configuration], and the set the agent runs as may declare
/// [ReapplyCalicoManifest.natPortRangeVariable] in its environment. THE ENVIRONMENT OUTRANKS THE
/// SETTINGS OBJECT: the agent builds its configuration from its environment, then its own file, then
/// the per-machine settings, then the global ones, and a lower source never overwrites a higher one.
/// So where the set declares that variable, patching [configuration] changes nothing at all — and
/// this step says that rather than reporting an alignment it did not make.
///
/// **No pod is replaced here, and that is measured rather than assumed.** The agent watches this
/// setting and repaints its own rules when it changes: on the machine above, the patch alone was
/// enough — the same pod went from 11 of 20 to 20 of 20 with no pod of the agent replaced. The
/// neighbouring step that pins which TABLE the agent programs replaces them, because a table the
/// agent is already painting into is not left by a repaint; a source-port range is one field of the
/// rule the agent rewrites anyway.
///
/// **What this step proves is the range the agent is CONFIGURED with, and not the ports a packet
/// leaving the machine actually carries.** Where those two come apart is inside the agent, which
/// nothing here can ask from the cluster side; the rules follow the configuration, and the
/// configuration is what is read back.
final class AlignCalicoNatPortRange extends ReversibleStep<String?> {
  /// Ensures the network agent masquerades out of [portRange].
  const AlignCalicoNatPortRange({this.portRange, this.kubectl = const Kubectl()});

  /// Builds the step from what the program gave it.
  factory AlignCalicoNatPortRange.fromArguments(Arguments arguments) => AlignCalicoNatPortRange(
    portRange: arguments.optionalText('port_range'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // Read as optional and declared as optional, because a row fills it from a MEASUREMENT: every
    // surface that describes a program before it runs builds the step, and at that moment the run
    // has not happened and the value does not exist. Without it the step has nothing to hold the
    // agent to and its check says so.
    ArgumentSpec(
      name: 'port_range',
      kind: ArgumentKind.text,
      describes:
          'the ports this machine opens its own connections from, taken from the row that '
          'measured it',
      required: false,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The object holding the agent's own settings.
  static const String configuration = 'felixconfiguration/default';

  /// The ports this machine opens its own connections from, passed from a measurement.
  final String? portRange;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? wanted = _wanted;
    if (wanted == null) {
      return CheckResult.blocked(
        portRange == null
            ? 'nothing measured which ports this machine opens its own connections from, so there '
                  'is nothing to hold the agent to and its masquerade must not be narrowed to a '
                  'guess'
            : '"$portRange" is no port range — a measurement of this machine names two port '
                  'numbers between $_lowestPort and $_highestPort, the lower one first',
      );
    }
    final String? live = await _live(context);
    if (live == null) {
      return const CheckResult.blocked(
        '$configuration could not be read — the network agent has to be up before its masquerade '
        'can be held to a range',
      );
    }
    final String? started = await ReapplyCalicoManifest.declaredEnv(
      context,
      kubectl,
      ReapplyCalicoManifest.natPortRangeVariable,
    );
    if (started == null) {
      return const CheckResult.blocked(
        '${ReapplyCalicoManifest.daemonSet} could not be read, so nothing says whether the agent is '
        'started with a range of its own — and one that is would decide this instead of '
        '$configuration',
      );
    }
    if (started.isNotEmpty) {
      // The value the agent STARTS with outranks the one it is patched with, so what stands here is
      // read and reported, never overwritten. Aligning it means changing the manifest the set is
      // applied from, which belongs to whoever owns that file.
      return _asRange(started) == wanted
          ? CheckResult.satisfied(
              'the agent is started with '
              '${ReapplyCalicoManifest.natPortRangeVariable}=$started, and this machine opens its '
              'own connections from ports $portRange',
            )
          : CheckResult.blocked(
              'the agent is started with '
              '${ReapplyCalicoManifest.natPortRangeVariable}=$started while this machine opens its '
              'own connections from ports $portRange, and that outranks $configuration — so '
              'holding the agent to a range here would change nothing. The manifest the agent is '
              'applied from is where this is answered',
            );
    }
    if (_asRange(live) == wanted) {
      return CheckResult.satisfied(
        'the agent masquerades out of $live, and this machine opens its own connections from ports '
        '$portRange',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // A dry run happens before the row above this one has measured anything, so there is no range to
    // name yet. What is reported is that, and not a command built around a range chosen here.
    final String? wanted = _wanted;
    return wanted == null
        ? const StepPlan.nothing(
            'the row above this one measures which ports this machine opens its own connections '
            'from, and until that has run there is nothing here to hold the agent to',
          )
        : StepPlan.argv(kubectl.argv(_patch(wanted)));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String wanted = _measured;
    await _mustRun(context, _patch(wanted));
    context.log.info(
      'the network agent masquerades the pod network out of ports $wanted, the ports this machine '
      'opens its own connections from',
    );
  }

  /// The range the agent masquerades out of, read before it is held to this machine's.
  ///
  /// The empty string is the agent carrying no range at all, and null is the object being
  /// unreadable. Reading it after the apply would read the range this step wrote.
  @override
  Future<String?> capture(StepContext context) => _live(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    // An agent that carried no range masquerades out of the whole port space, and the way to put
    // that back is to take the field away again — which is what a merge patch does with a null.
    // Writing the widest range instead would leave a field standing that was not there before.
    await _mustRun(context, _patch(captured.isEmpty ? null : captured));
  }

  /// The agent's range, the empty string when it has none, or null when it cannot be read.
  Future<String?> _live(StepContext context) async {
    final CommandResult live = await context.shell.run(
      kubectl.observing(<String>['get', configuration, '-o', 'jsonpath={.spec.natPortRange}']),
    );
    return live.ok ? live.trimmed : null;
  }

  /// What the agent has to carry to masquerade into the same ports this machine uses, or null where
  /// nothing measured the machine and where what was measured is no port range.
  String? get _wanted => portRange == null ? null : _asRange(portRange!);

  /// The same, for the members that run only after [check] has admitted the step.
  ///
  /// [check] blocks where this would be null, and a blocked step is neither planned nor applied. It
  /// throws rather than falling back to a range: an apply that chose one would narrow the cluster's
  /// masquerade to ports nobody measured, and then report that it had aligned the two.
  String get _measured =>
      _wanted ??
      (throw StateError(
        'no measurement said which ports this machine opens its own connections from',
      ));

  /// [value] as the agent spells a port range, or null where it is no port range.
  ///
  /// Two port numbers, the lower one first. The machine writes them with whitespace between and the
  /// agent writes them with a colon, and both are read here so the value handed over by the row that
  /// measured the machine and the value read back out of the cluster pass through one reading. Two
  /// spellings compared as text would make a step that had already done its work ask for it again on
  /// every run.
  ///
  /// [_lowestPort] and [_highestPort] are what a port number is, so anything outside them is not one
  /// and the value is refused rather than written into the cluster.
  static String? _asRange(String value) {
    final List<String> numbers = value
        .split(RegExp(r'[\s:]+'))
        .where((String each) => each.isNotEmpty)
        .toList();
    if (numbers.length != 2) {
      return null;
    }
    final int? low = int.tryParse(numbers.first);
    final int? high = int.tryParse(numbers.last);
    if (low == null || high == null) {
      return null;
    }
    if (low < _lowestPort || high > _highestPort || low > high) {
      return null;
    }
    return '$low:$high';
  }

  /// The lowest port number that exists, so a reading below it names no port.
  static const int _lowestPort = 1;

  /// The highest port number that exists, so a reading above it names no port.
  static const int _highestPort = 65535;

  /// The patch that writes [range], or takes the field away again where it is null.
  List<String> _patch(String? range) => <String>[
    'patch',
    configuration,
    '--type',
    'merge',
    '-p',
    jsonEncode(<String, Object>{
      'spec': <String, String?>{'natPortRange': range},
    }),
  ];

  Future<void> _mustRun(StepContext context, List<String> arguments) async {
    final Command command = kubectl.command(arguments);
    final CommandResult answer = await context.shell.run(command);
    if (!answer.ok) {
      throw CommandFailed(
        argv: command.argv,
        exitCode: answer.exitCode,
        stdout: '',
        stderr: answer.stderr,
      );
    }
  }
}
