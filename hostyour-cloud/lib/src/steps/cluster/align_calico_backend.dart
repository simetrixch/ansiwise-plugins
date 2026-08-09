import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'detect_host_iptables_backend.dart';
import 'reapply_calico_manifest.dart';

/// Pins the network agent to the same packet-filtering backend the machine is on.
///
/// **The agent's own guess is wrong on the kernel this platform runs.** It normally works the
/// backend out for itself, and on a recent kernel it can settle on the older one while the machine
/// is on the modern one. The two sets of rules then do not see each other, and what an operator
/// notices is name lookups from inside the cluster timing out — a symptom that says nothing about
/// packet filtering at all, which is why this step exists rather than being left to the agent.
///
/// **Only the agent's configuration is touched, and never the rules themselves.** An earlier version
/// of this emptied the other backend's tables, and on a working machine that took the translation
/// rules for published ports with it and broke the ingress path silently. The agent removes its own
/// stale rules when it repaints; nothing here has to.
///
/// **Left alone means left alone.** An agent that is set to work the backend out for itself is not
/// changed, because pinning it would be a change nobody asked for and a needless replacement of
/// every agent pod with it.
final class AlignCalicoBackend extends ReversibleStep {
  /// Pins the agent to the machine's backend, giving the replacement [rolloutTimeoutSeconds].
  const AlignCalicoBackend({required this.rolloutTimeoutSeconds});

  /// Builds the step from what the program gave it.
  factory AlignCalicoBackend.fromArguments(Arguments arguments) =>
      AlignCalicoBackend(rolloutTimeoutSeconds: arguments.integer('rollout_timeout_seconds'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'rollout_timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the network agent is given to be replaced after it is pinned',
      required: false,
      defaultValue: 120,
    ),
  ];

  /// The object holding the agent's own settings.
  static const String configuration = 'felixconfiguration/default';

  /// The value that means the agent works the backend out for itself.
  static const String auto = 'Auto';

  /// How long the replacement is given.
  final int rolloutTimeoutSeconds;

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
    final String wanted = _wanted(await DetectHostIptablesBackend.detect(context));
    if (live == wanted) {
      return CheckResult.satisfied('the agent and this machine both filter packets with $live');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String wanted = _wanted(await DetectHostIptablesBackend.detect(context));
    return StepPlan.argv(_patch(wanted));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String backend = await DetectHostIptablesBackend.detect(context);
    context.log.info(
      'this machine filters packets with $backend — pinning the network agent to it',
    );
    await _mustRun(context, _patch(_wanted(backend)));
    await _rollAgent(context);
  }

  @override
  Future<void> undo(StepContext context) async {
    await _mustRun(context, _patch(auto));
    await _rollAgent(context);
  }

  /// The agent's pinned backend, the empty string when it has none, or null when it cannot be read.
  static Future<String?> _live(StepContext context) async {
    final CommandResult live = await context.shell.run(
      const Command.observing('microk8s', <String>[
        'kubectl',
        'get',
        configuration,
        '-o',
        'jsonpath={.spec.iptablesBackend}',
      ]),
    );
    return live.ok ? live.trimmed : null;
  }

  /// What the agent calls the backend this machine calls [backend].
  static String _wanted(String backend) =>
      backend == DetectHostIptablesBackend.legacy ? 'Legacy' : 'NFT';

  static List<String> _patch(String backend) => <String>[
    'microk8s',
    'kubectl',
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
      const Command('microk8s', <String>[
        'kubectl',
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'restart',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
      ]),
    );
    await context.shell.run(
      Command('microk8s', <String>[
        'kubectl',
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'status',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
        '--timeout=${rolloutTimeoutSeconds}s',
      ]),
    );
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }
}
