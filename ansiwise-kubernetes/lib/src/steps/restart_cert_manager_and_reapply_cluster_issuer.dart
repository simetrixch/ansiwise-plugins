import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';

/// The one recovery an issuer that did not register gets, and the end of the budget for it.
///
/// **Waiting longer does not help.** An account that has not registered by the time the first wait
/// is up is stuck rather than slow, and what it is usually stuck on is a certificate service holding
/// network state from before the cluster's own network was finished. Restarting it and applying the
/// issuer again is what clears that; another minute of polling is not.
///
/// **The budget ends here on purpose.** Every certificate on this cluster waits on this issuer, and
/// a run that goes on waiting hides that; a run that reports the failure lets somebody go and look.
///
/// **This does nothing at all when the issuer is already registered**, which is what it looks like
/// on every run where the first wait was enough.
final class RestartCertManagerAndReapplyClusterIssuer extends IrreversibleStep {
  /// Restarts the certificate service and applies [name] again, then waits [waitSeconds].
  const RestartCertManagerAndReapplyClusterIssuer({
    required this.name,
    required this.namespace,
    required this.deployments,
    required this.manifestPath,
    required this.settleSeconds,
    required this.waitSeconds,
    required this.intervalSeconds,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory RestartCertManagerAndReapplyClusterIssuer.fromArguments(Arguments arguments) =>
      RestartCertManagerAndReapplyClusterIssuer(
        name: arguments.text('name'),
        namespace: arguments.text('namespace'),
        deployments: arguments.textList('deployments'),
        manifestPath: arguments.text('issuer_manifest_path'),
        settleSeconds: arguments.integer('settle_seconds'),
        waitSeconds: arguments.integer('wait_seconds'),
        intervalSeconds: arguments.integer('interval_seconds'),
        kubectl: Kubectl.fromArguments(arguments),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes:
          'the issuer every certificate on this cluster is issued by — what it is called is a '
          'fact about the installation',
    ),
    // Neither the namespace nor the names of the parts has a default. Both are decided by how the
    // certificate service was INSTALLED — a release under another name gives its deployments that
    // name and can be put in any namespace — and this package did not install it. A default would
    // roll nothing on such a cluster while every command still returned zero, and the issuer would
    // be applied again to the same stuck service.
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the certificate service runs in',
    ),
    ArgumentSpec(
      name: 'deployments',
      kind: ArgumentKind.textList,
      describes:
          'the deployments of the certificate service that are restarted, under the names the '
          'release that installed it gave them',
    ),
    ArgumentSpec(
      name: 'issuer_manifest_path',
      kind: ArgumentKind.text,
      describes:
          'the file the rendered issuer stands in, as the step that renders it writes it — one '
          'value, so the writer and this cannot come to name different files',
    ),
    ArgumentSpec(
      name: 'settle_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 3600,
        because:
            'a pause of zero seconds is no pause, and one longer than an hour is a wait rather than a settle',
      ),
      describes: 'how long the restarted service is left before the issuer is applied again',
      required: false,
      defaultValue: 15,
    ),
    ArgumentSpec(
      name: 'wait_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 86400,
        because:
            'a bound of zero seconds gives up before it looks, and one longer than a day outlives the run it bounds',
      ),
      describes: 'how long the second registration is given, after which the run reports a failure',
      required: false,
      defaultValue: 60,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 1,
        most: 3600,
        because:
            'a gap of zero seconds asks without pausing, and one longer than an hour is a wait rather than a gap between looks',
      ),
      describes: 'how long to leave between looks',
      required: false,
      defaultValue: 10,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// The namespace the certificate service runs in.
  final String namespace;

  /// The deployments of the certificate service that are restarted.
  final List<String> deployments;

  /// The manifest this step applies again.
  final String manifestPath;

  /// How long the restarted service is left.
  final int settleSeconds;

  /// How long the second registration is given.
  final int waitSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  String get irreversibleReason =>
      'the issuer was deleted and applied again, and the parts of the certificate service that were '
      'running are gone. The account key in the secret of the same name stays, so what comes back is '
      'the registration that key belongs to rather than a new one — and the requests the restarted '
      'parts were in the middle of are not made again';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await isReady(context, kubectl, name)) {
      return CheckResult.satisfied('$name reports that its account is registered');
    }
    if (!await context.files.exists(manifestPath, elevated: elevated)) {
      return CheckResult.blocked('$manifestPath is not there, so there is nothing to apply again');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    'would restart the certificate service, apply $name again and give the registration another '
    '${waitSeconds}s — and report a failure if it still has not happened',
  );

  @override
  Future<void> apply(StepContext context) async {
    context.log.warn(
      '$name has not registered. Restarting the certificate service and applying it again — this is '
      'the one recovery it gets.',
    );
    for (final String deployment in deployments) {
      await context.shell.run(
        kubectl.command(<String>['-n', namespace, 'rollout', 'restart', 'deployment/$deployment']),
      );
    }
    await context.clock.sleep(Duration(seconds: settleSeconds));

    await context.shell.run(kubectl.command(<String>['delete', 'clusterissuer', name]));
    await context.clock.sleep(const Duration(seconds: 5));

    final Command apply = kubectl.command(<String>['apply', '-f', manifestPath]);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(
        argv: apply.argv,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }

    final DateTime giveUp = context.clock.now().add(Duration(seconds: waitSeconds));
    while (!await isReady(context, kubectl, name)) {
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(
          waitingFor:
              "$name's account to register. Two waits and a restart of the certificate service "
              'have passed, so it is stuck rather than slow — and every certificate on this cluster '
              'is waiting on it',
          deadline: Duration(seconds: waitSeconds),
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  /// Whether [name] reports itself ready.
  ///
  /// An issuer that has just been applied carries no conditions at all, and reading them then gives
  /// nothing rather than an answer — which is not ready, and is not an error either. A reader that
  /// expected the conditions to be there would fail on the very state it is meant to report.
  static Future<bool> isReady(StepContext context, Kubectl kubectl, String name) async {
    final CommandResult condition = await context.shell.run(
      kubectl.observing(<String>[
        'get',
        'clusterissuer',
        name,
        '-o',
        'jsonpath={.status.conditions[?(@.type=="Ready")].status}',
      ]),
    );
    return condition.ok && condition.trimmed == 'True';
  }
}
