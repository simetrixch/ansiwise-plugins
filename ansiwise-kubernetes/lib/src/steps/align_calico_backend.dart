import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';
import 'reapply_calico_manifest.dart';

/// Pins the network agent to the same packet-filtering backend the machine is on.
///
/// **The agent's own guess can be wrong on a recent kernel.** It normally works the backend out for
/// itself, and it can settle on the older one while the machine is on the modern one. The two sets
/// of rules then do not see each other, and what an operator notices is name lookups from inside
/// the cluster timing out — a symptom that says nothing about packet filtering at all, which is why
/// this step exists rather than being left to the agent.
///
/// **Only the agent's configuration is touched, and never the rules themselves.** An earlier version
/// of this emptied the other backend's tables, and on a working machine that took the translation
/// rules for published ports with it and broke the ingress path silently. The agent removes its own
/// stale rules when it repaints; nothing here has to.
///
/// **Left alone means left alone.** An agent that is set to work the backend out for itself is not
/// changed, because pinning it would be a change nobody asked for and a needless replacement of
/// every agent pod with it.
final class AlignCalicoBackend extends ReversibleStep<String?> {
  /// Ensures the Calico node pods are running with the given [backend].
  const AlignCalicoBackend({
    required this.rolloutTimeoutSeconds,
    this.backend,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory AlignCalicoBackend.fromArguments(Arguments arguments) => AlignCalicoBackend(
    rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'),
    backend: arguments.optionalText('backend'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the network agent is given to be replaced after it is pinned',
      required: false,
      defaultValue: 120,
    ),
    ArgumentSpec(
      name: 'backend',
      kind: ArgumentKind.text,
      describes: 'the packet-filtering backend the machine is on, passed from a measurement',
      required: false,
    ),
    Kubectl.argument,
  ];

  /// The object holding the agent's own settings.
  static const String configuration = 'felixconfiguration/default';

  /// The value that means the agent works the backend out for itself.
  static const String auto = 'Auto';

  /// How long the replacement is given.
  final int rolloutTimeoutSeconds;

  /// The packet-filtering backend the machine is on, passed from a measurement.
  final String? backend;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? live = await _live(context);
    if (live == null) {
      return const CheckResult.blocked(
        '$configuration could not be read — the network agent has to be up before it can be pinned',
      );
    }
    if (live.isEmpty || live == auto) {
      return const CheckResult.satisfied(
        'the agent is set to work the backend out for itself, and pinning it would be a change '
        'nobody asked for',
      );
    }
    final String? measured = await _machineBackend(context, backend);
    if (measured == null) {
      // Nothing read the machine, so there is nothing to pin the agent TO. Pinning it to the
      // fallback would set the cluster's packet filtering from a value nobody measured, and the
      // step would report that it aligned the two.
      return const CheckResult.blocked(
        'neither /etc/alternatives/iptables nor /usr/sbin/iptables could be read, so nothing says '
        'which backend this machine filters packets with, and the agent must not be pinned to a '
        'guess',
      );
    }
    if (live == _wanted(measured)) {
      return CheckResult.satisfied('the agent and this machine both filter packets with $live');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // check blocks when nothing could be read, and a blocked step is never planned - so by here a
    // reading exists. Stated rather than asserted with a null check nobody can reach.
    final String measured = await _machineBackend(context, backend) ?? _nft;
    return StepPlan.argv(kubectl.argv(_patch(_wanted(measured))));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String measured = await _machineBackend(context, backend) ?? _nft;
    context.log.debug(
      'this machine filters packets with $measured — pinning the network agent to it',
    );
    await _mustRun(context, _patch(_wanted(measured)));
    await _rollAgent(context);
  }

  /// The backend the agent is pinned to, read before it is pinned to this machine's.
  ///
  /// The empty string is the agent carrying no pin at all, and null is the object being unreadable.
  /// Reading it after the apply would read the pin this step wrote.
  @override
  Future<String?> capture(StepContext context) => _live(context);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    // An agent with no pin works the backend out for itself, so that is what the empty reading is
    // put back as.
    await _mustRun(context, _patch(captured.isEmpty ? auto : captured));
    await _rollAgent(context);
  }

  /// The agent's pinned backend, the empty string when it has none, or null when it cannot be read.
  Future<String?> _live(StepContext context) async {
    final CommandResult live = await context.shell.run(
      kubectl.observing(<String>['get', configuration, '-o', 'jsonpath={.spec.iptablesBackend}']),
    );
    return live.ok ? live.trimmed : null;
  }

  /// The older backend, as the machine's own tooling names it.
  static const String _legacy = 'legacy';

  /// The modern backend, and what an unreadable machine is reported as.
  static const String _nft = 'nft';

  /// Which packet-filtering backend this machine's own tooling is set to.
  ///
  /// The machine chooses between the two by a link, and which one it points at is what the agent
  /// has to be pinned to. The fallback direction is chosen rather than accidental: a machine this
  /// cannot read is reported as being on the modern backend, the default of every recent release
  /// and the safer of the two to be wrong about — pinning the agent to the older one on a machine
  /// that is really on the modern one is the split this measurement exists to prevent.
  ///
  /// **This is a SECOND reading of the same link, and the package that owns the machine's own
  /// tooling carries the first.** That is stated rather than hidden, because the two can come to
  /// disagree and nothing would report it: the tool packages do not depend on one another, and the
  /// framework carries no channel by which a step that MEASURED something hands the value to a
  /// later step — a predicate answers yes or no, and an answer comes from the operator. Until there
  /// is such a channel there are two readings, and this is where that costs somebody something.
  /// **Null is not a value, it is the absence of a reading.** Answering with a backend when neither
  /// link could be read would make "the machine filters with nft" and "nothing here could be read"
  /// the same answer, and this step would then align the agent to a backend nobody measured.
  static Future<String?> _machineBackend(StepContext context, String? providedBackend) async {
    if (providedBackend != null) {
      return providedBackend;
    }
    for (final List<String> argv in <List<String>>[
      <String>['readlink', '-f', '/etc/alternatives/iptables'],
      <String>['readlink', '-f', '/usr/sbin/iptables'],
    ]) {
      final CommandResult resolved = await context.shell.run(
        Command.observing(argv.first, argv.sublist(1)),
      );
      if (!resolved.ok) {
        continue;
      }
      final String target = resolved.trimmed;
      if (target.contains(_legacy)) {
        return _legacy;
      }
      if (target.contains(_nft)) {
        return _nft;
      }
    }
    return null;
  }

  /// What the agent calls the backend this machine calls [backend].
  static String _wanted(String backend) => backend == _legacy ? 'Legacy' : 'NFT';

  List<String> _patch(String backend) => <String>[
    'patch',
    configuration,
    '--type',
    'merge',
    '-p',
    jsonEncode(<String, Object>{
      'spec': <String, String>{'iptablesBackend': backend},
    }),
  ];

  Future<void> _rollAgent(StepContext context) async {
    await context.shell.run(
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'restart',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
      ]),
    );
    await context.shell.run(
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'status',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
        '--timeout=${rolloutTimeoutSeconds}s',
      ]),
    );
  }

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
