import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';
import 'reapply_calico_manifest.dart';

/// Holds the network agent to the packet-filtering backend this machine filters with.
///
/// **The question is which table the agent PROGRAMS, and a setting that defers the answer is not an
/// answer to it.** The agent's own settings carry a value meaning "work it out later", and on a
/// machine filtering with the modern backend the agent worked it out as the older one. The
/// masquerade for the pod network was then written into a table that does not govern, and nothing
/// inside the cluster could reach anything outside the machine. None of what that produces reads as
/// a network fault — images fail to pull naming no cause, a public repository cannot be listed, and
/// everything that reaches outward sits at its timeout — which is why the backend is pinned here
/// rather than left to be decided.
///
/// **So there is no branch that leaves the agent on "work it out later".** A machine where the agent
/// would have chosen correctly ends on the very backend it would have chosen, and it ends there
/// because this run measured the machine and wrote the answer down. That is a different thing from
/// the same answer arrived at by luck, and only the first of the two is a value this run can name.
///
/// **Two places carry the backend, and only one of them is this step's.** The agent's settings
/// object holds it at [configuration], and the set the agent runs as may declare
/// [ReapplyCalicoManifest.backendVariable] in its environment. THE ENVIRONMENT OUTRANKS THE SETTINGS
/// OBJECT: the agent builds its configuration from its environment, then its own file, then the
/// per-machine settings, then the global ones, and a lower source never overwrites a higher one. So
/// where the set declares that variable, patching [configuration] changes nothing at all — and this
/// step says that rather than reporting an alignment it did not make. Where it would be changed is
/// the manifest the set is applied from, and that file is not this step's.
///
/// **What this machine filters with is not read here.** It arrives as [backend] from the row that
/// measured it. Reading the machine again in this package would be a second answer to one question,
/// and two answers can disagree with nothing to report it.
///
/// **Only the agent's configuration is touched, and never the rules themselves.** Emptying the
/// other backend's tables takes the translation rules for published ports with it and breaks the
/// ingress path on a working machine, silently. The agent removes its own stale rules when it
/// repaints; nothing here has to.
///
/// **The agent's pods are replaced after the pin, and what that is worth is stated rather than
/// assumed.** The agent reads this parameter when it starts and restarts itself when the value
/// changes — measured on a machine, the rules moved into the right table within about a minute with
/// no pod replaced. Replacing them is how the value is taken promptly instead of at some later
/// restart, and a replacement that does not converge inside its window is written into the record:
/// the pin stands either way, and the agent takes it when it next starts.
///
/// **What this step proves is the backend the agent is CONFIGURED with, and not a count of rules on
/// the machine.** Where those two come apart is inside the agent, which nothing here can ask from
/// the cluster side; the rules follow the configuration, and the configuration is what is read back.
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
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      describes: 'how long the network agent is given to be replaced after it is pinned',
      required: false,
      defaultValue: 120,
    ),
    // Read as optional and declared as optional, because a row fills it from a MEASUREMENT: every
    // surface that describes a program before it runs builds the step, and at that moment the run
    // has not happened and the value does not exist. Without it the step has nothing to hold the
    // agent to and its check says so.
    ArgumentSpec(
      name: 'backend',
      kind: ArgumentKind.text,
      describes:
          'the packet-filtering backend this machine is on, taken from the row that measured it',
      required: false,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The object holding the agent's own settings.
  static const String configuration = 'felixconfiguration/default';

  /// The value that means the agent works the backend out for itself.
  static const String auto = 'Auto';

  /// How long the replacement is given.
  final int rolloutTimeoutSeconds;

  /// The packet-filtering backend this machine is on, passed from a measurement.
  final String? backend;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? pin = _pin;
    if (pin == null) {
      return CheckResult.blocked(
        backend == null
            ? 'nothing measured which backend this machine filters packets with, so there is '
                  'nothing to hold the agent to and it must not be pinned to a guess'
            : '"$backend" is not a backend this step knows — a measurement of this machine names '
                  'either $_nft or $_legacy',
      );
    }
    final String? live = await _live(context);
    if (live == null) {
      return const CheckResult.blocked(
        '$configuration could not be read — the network agent has to be up before it can be pinned',
      );
    }
    final String? started = await ReapplyCalicoManifest.declaredEnv(
      context,
      kubectl,
      ReapplyCalicoManifest.backendVariable,
    );
    if (started == null) {
      return const CheckResult.blocked(
        '${ReapplyCalicoManifest.daemonSet} could not be read, so nothing says whether the agent is '
        'started with a backend of its own — and one that is would decide this instead of '
        '$configuration',
      );
    }
    if (started.isNotEmpty) {
      // The value the agent STARTS with outranks the one it is patched with, so what stands here is
      // read and reported, never overwritten. Aligning it means changing the manifest the set is
      // applied from, which belongs to whoever owns that file.
      return _names(started, pin)
          ? CheckResult.satisfied(
              'the agent is started with ${ReapplyCalicoManifest.backendVariable}=$started, and '
              'this machine filters packets with $backend',
            )
          : CheckResult.blocked(
              'the agent is started with ${ReapplyCalicoManifest.backendVariable}=$started while '
              'this machine filters packets with $backend, and that outranks $configuration — so '
              'pinning the agent here would change nothing. The manifest the agent is applied from '
              'is where this is answered',
            );
    }
    if (_names(live, pin)) {
      return CheckResult.satisfied(
        'the agent is pinned to $live and this machine filters packets with $backend',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    // A dry run happens before the row above this one has measured anything, so there is no backend
    // to name yet. What is reported is that, and not a command built around a backend chosen here.
    final String? pin = _pin;
    return pin == null
        ? const StepPlan.nothing(
            'the row above this one measures which backend this machine filters packets with, and '
            'until that has run there is nothing here to pin the network agent to',
          )
        : StepPlan.argv(kubectl.argv(_patch(pin)));
  }

  @override
  Future<void> apply(StepContext context) async {
    final String pin = _pinned;
    await _mustRun(context, _patch(pin));
    context.log.info(
      'the network agent is pinned to $pin, the backend this machine filters packets with',
    );
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

  /// The modern backend, as the machine's own tooling names it.
  static const String _nft = 'nft';

  /// What the agent has to carry to program the same table this machine filters with, or null where
  /// nothing measured the machine and where what was measured is not one of the two backends.
  String? get _pin => switch (backend) {
    _legacy => 'Legacy',
    _nft => 'NFT',
    _ => null,
  };

  /// The same, for the members that run only after [check] has admitted the step.
  ///
  /// [check] blocks where this would be null, and a blocked step is neither planned nor applied. It
  /// throws rather than falling back to a backend: an apply that chose one would set the cluster's
  /// packet filtering from a value nobody measured, and then report that it had aligned the two.
  String get _pinned =>
      _pin ??
      (throw StateError('no measurement said which backend this machine filters packets with'));

  /// Whether [value] names [pin], however it is spelled.
  ///
  /// The settings object holds one of three spellings the cluster validates. The set's environment
  /// is plain text nothing validates, and the agent reads a value there without regard to case.
  static bool _names(String value, String pin) => value.toLowerCase() == pin.toLowerCase();

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

  /// Replaces the agent's pods and waits for the replacement, saying so where it does not converge.
  ///
  /// A replacement that runs past its window does not cost the pin — the agent takes this parameter
  /// when it next starts, and it restarts itself when the value changes. What it costs is the
  /// promptness this replacement was asked for, so it is written at a level the run keeps rather
  /// than passed over silently.
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
    final CommandResult converged = await context.shell.run(
      kubectl.command(<String>[
        '-n',
        ReapplyCalicoManifest.namespace,
        'rollout',
        'status',
        'daemonset/${ReapplyCalicoManifest.daemonSet}',
        '--timeout=${rolloutTimeoutSeconds}s',
      ]),
    );
    if (!converged.ok) {
      context.log.warn(
        'the network agent was not finished being replaced within ${rolloutTimeoutSeconds}s — the '
        'backend it is pinned to stands, and it takes that backend when it next starts',
      );
    }
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
