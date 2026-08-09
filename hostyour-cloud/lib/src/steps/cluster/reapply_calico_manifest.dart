import 'package:ansiwise_api/ansiwise_api.dart';
import 'stamp_calico_pool_cidr_in_cni_manifest.dart';

/// Puts the stamped network manifest into the cluster, so Calico carries the new range.
///
/// **What is checked afterwards is what the cluster holds, not what the command returned.** An apply
/// that matched nothing returns zero just as happily as one that changed everything. The value this
/// step exists to move is the pool range Calico is started with, and that value is readable straight
/// out of the running set: it is on the container the network agent runs in, and it is there the
/// moment the apply is accepted.
///
/// The pool itself is not built again here. That happens when the agent restarts, which is the step
/// after this one, and whether it converged is the step after that.
final class ReapplyCalicoManifest extends ReversibleStep<String?> {
  /// Applies the manifest at [manifestPath], which must already carry [podCidr].
  const ReapplyCalicoManifest({required this.podCidr, required this.manifestPath});

  /// Builds the step from what the program gave it.
  factory ReapplyCalicoManifest.fromArguments(Arguments arguments) => ReapplyCalicoManifest(
    podCidr: arguments.text('pod_cidr'),
    manifestPath: arguments.text('manifest_path'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'manifest_path',
      kind: ArgumentKind.text,
      describes: 'the network manifest Calico builds the pool from',
      required: false,
      defaultValue: StampCalicoPoolCidrInCniManifest.defaultPath,
    ),
  ];

  /// The namespace the network agent runs in.
  static const String namespace = 'kube-system';

  /// The set the network agent runs as, one on every machine of the cluster.
  static const String daemonSet = 'calico-node';

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The manifest that is applied.
  final String manifestPath;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(manifestPath)) {
      return CheckResult.blocked('$manifestPath is not there, so there is nothing to apply');
    }
    final String manifest = await context.files.read(manifestPath);
    if (!manifest.contains(podCidr)) {
      return CheckResult.blocked(
        '$manifestPath does not carry $podCidr — applying it would put the old range back into the '
        'cluster',
      );
    }
    if (await declaredPoolCidr(context) == podCidr) {
      return CheckResult.satisfied('$daemonSet in the cluster is declared with $podCidr');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_argv(manifestPath));

  @override
  Future<void> apply(StepContext context) async {
    await _apply(context, manifestPath);
  }

  /// The newest backup of the manifest, named before the stamped one is applied.
  ///
  /// The step that stamps the manifest writes a timestamped backup on every real change, so the
  /// newest one read at undo time can be a copy a later run made — and applying that would put a
  /// range into the cluster that nothing in this run ever had.
  @override
  Future<String?> capture(StepContext context) =>
      StampCalicoPoolCidrInCniManifest.newestBackup(context, manifestPath);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    await _apply(context, captured);
  }

  /// The range the network agent is declared with in the cluster, or null when it cannot be read.
  static Future<String?> declaredPoolCidr(StepContext context) async {
    final CommandResult declared = await context.shell.run(
      const Command.observing('microk8s', <String>[
        'kubectl',
        '-n',
        namespace,
        'get',
        'daemonset',
        daemonSet,
        '-o',
        'jsonpath={.spec.template.spec.containers[0].env'
            '[?(@.name=="${StampCalicoPoolCidrInCniManifest.variable}")].value}',
      ]),
    );
    return declared.ok && declared.trimmed.isNotEmpty ? declared.trimmed : null;
  }

  static Future<void> _apply(StepContext context, String path) async {
    final List<String> argv = _argv(path);
    final CommandResult applied = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!applied.ok) {
      throw CommandFailed(argv: argv, exitCode: applied.exitCode, stderr: applied.stderr);
    }
  }

  static List<String> _argv(String path) => <String>['microk8s', 'kubectl', 'apply', '-f', path];
}
