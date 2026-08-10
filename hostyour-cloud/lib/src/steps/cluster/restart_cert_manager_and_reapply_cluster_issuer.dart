import 'package:ansiwise_api/ansiwise_api.dart';
import 'configure_slave_apiserver_oidc_trust.dart';

/// The one recovery an issuer that did not register gets, and the end of the budget for it.
///
/// **Waiting longer does not help.** An account that has not registered by the time the first wait
/// is up is stuck rather than slow, and what it is usually stuck on is a certificate service holding
/// network state from before the cluster's own network was finished. Restarting it and applying the
/// issuer again is what clears that; another minute of polling is not.
///
/// **The budget ends here on purpose.** Every certificate on this cluster waits on this issuer, and
/// one of them holds up the secret store's own start — which is what holds the keys that unlock it.
/// A run that goes on waiting hides that; a run that reports the failure lets somebody go and look.
///
/// **This does nothing at all when the issuer is already registered**, which is what it looks like
/// on every run where the first wait was enough.
final class RestartCertManagerAndReapplyClusterIssuer extends IrreversibleStep {
  /// Restarts the certificate service and applies [name] again, then waits [waitSeconds].
  const RestartCertManagerAndReapplyClusterIssuer({
    required this.name,
    required this.namespace,
    required this.stateDirectory,
    required this.settleSeconds,
    required this.waitSeconds,
    required this.intervalSeconds,
  });

  /// Builds the step from what the program gave it.
  factory RestartCertManagerAndReapplyClusterIssuer.fromArguments(Arguments arguments) =>
      RestartCertManagerAndReapplyClusterIssuer(
        name: arguments.text('name'),
        namespace: arguments.text('namespace'),
        stateDirectory: arguments.text('state_directory'),
        settleSeconds: arguments.integer('settle_seconds'),
        waitSeconds: arguments.integer('wait_seconds'),
        intervalSeconds: arguments.integer('interval_seconds'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the issuer every certificate on this cluster is issued by',
      required: false,
      defaultValue: 'letsencrypt-prod',
    ),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace the certificate service runs in',
      required: false,
      defaultValue: defaultNamespace,
    ),
    ArgumentSpec(
      name: 'state_directory',
      kind: ArgumentKind.text,
      describes: 'where this program keeps the manifests it renders',
      required: false,
      defaultValue: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
    ),
    ArgumentSpec(
      name: 'settle_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the restarted service is left before the issuer is applied again',
      required: false,
      defaultValue: 15,
    ),
    ArgumentSpec(
      name: 'wait_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the second registration is given, after which the run reports a failure',
      required: false,
      defaultValue: 60,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks',
      required: false,
      defaultValue: 10,
    ),
  ];

  /// Where the certificate service runs.
  static const String defaultNamespace = 'cert-manager';

  /// The parts of the certificate service that are restarted.
  static const List<String> deployments = <String>[
    'cert-manager',
    'cert-manager-webhook',
    'cert-manager-cainjector',
  ];

  /// The issuer certificates are issued by.
  final String name;

  /// The namespace the certificate service runs in.
  final String namespace;

  /// Where the rendered manifest is.
  final String stateDirectory;

  /// How long the restarted service is left.
  final int settleSeconds;

  /// How long the second registration is given.
  final int waitSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// The manifest this step applies again.
  String get manifestPath => '$stateDirectory/clusterissuer.yaml';

  @override
  String get irreversibleReason =>
      'the issuer was deleted and applied again, and the parts of the certificate service that were '
      'running are gone. The account key in the secret of the same name stays, so what comes back is '
      'the registration that key belongs to rather than a new one — and the requests the restarted '
      'parts were in the middle of are not made again';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (await isReady(context, name)) {
      return CheckResult.satisfied('$name reports that its account is registered');
    }
    if (!await context.files.exists(manifestPath)) {
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
        Command('microk8s', <String>[
          'kubectl',
          '-n',
          namespace,
          'rollout',
          'restart',
          'deployment/$deployment',
        ]),
      );
    }
    await context.clock.sleep(Duration(seconds: settleSeconds));

    await context.shell.run(
      Command('microk8s', <String>['kubectl', 'delete', 'clusterissuer', name]),
    );
    await context.clock.sleep(const Duration(seconds: 5));

    final List<String> argv = <String>['microk8s', 'kubectl', 'apply', '-f', manifestPath];
    final CommandResult applied = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!applied.ok) {
      throw CommandFailed(argv: argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }

    final DateTime giveUp = context.clock.now().add(Duration(seconds: waitSeconds));
    while (!await isReady(context, name)) {
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
  static Future<bool> isReady(StepContext context, String name) async {
    final CommandResult condition = await context.shell.run(
      Command.observing('microk8s', <String>[
        'kubectl',
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
