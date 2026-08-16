import 'package:ansiwise_api/ansiwise_api.dart';
import 'kubectl.dart';

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
  const ReapplyCalicoManifest({
    required this.podCidr,
    required this.manifestPath,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory ReapplyCalicoManifest.fromArguments(Arguments arguments) => ReapplyCalicoManifest(
    podCidr: arguments.text('pod_cidr'),
    manifestPath: arguments.text('manifest_path'),
    kubectl: Kubectl.fromArguments(arguments),
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
      describes:
          'the network manifest Calico builds the pool from — where that file sits is a fact '
          'about the installation',
    ),
    Kubectl.argument,
  ];

  /// The namespace the network agent runs in.
  static const String namespace = 'kube-system';

  /// The set the network agent runs as, one on every machine of the cluster.
  static const String daemonSet = 'calico-node';

  /// The environment variable whose value is the pool's range, as Calico names it.
  static const String variable = 'CALICO_IPV4POOL_CIDR';

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The manifest that is applied.
  final String manifestPath;

  /// How the cluster is reached.
  final Kubectl kubectl;

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
    if (await declaredPoolCidr(context, kubectl) == podCidr) {
      return CheckResult.satisfied('$daemonSet in the cluster is declared with $podCidr');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(kubectl.argv(<String>['apply', '-f', manifestPath]));

  @override
  Future<void> apply(StepContext context) async {
    await _apply(context, manifestPath);
  }

  /// The newest backup of the manifest, named before the stamped one is applied.
  ///
  /// The step that stamps the manifest writes a copy to `<path>.bak.<moment>` before each real
  /// change, so the newest one read at undo time can be a copy a later run made — and applying that
  /// would put a range into the cluster that nothing in this run ever had.
  @override
  Future<String?> capture(StepContext context) => _newestBackup(context, manifestPath);

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured == null) {
      return;
    }
    await _apply(context, captured);
  }

  /// The range the network agent is declared with in the cluster, or null when it cannot be read.
  static Future<String?> declaredPoolCidr(StepContext context, Kubectl kubectl) async {
    final CommandResult declared = await context.shell.run(
      kubectl.observing(<String>[
        '-n',
        namespace,
        'get',
        'daemonset',
        daemonSet,
        '-o',
        'jsonpath={.spec.template.spec.containers[0].env[?(@.name=="$variable")].value}',
      ]),
    );
    return declared.ok && declared.trimmed.isNotEmpty ? declared.trimmed : null;
  }

  /// The newest timestamped backup of [path], or null when there is none.
  ///
  /// The `<name>.bak.<moment>` shape is the one the stamping step writes, and the moments sort as
  /// text — so the last name in order is the newest copy.
  static Future<String?> _newestBackup(StepContext context, String path) async {
    final int cut = path.lastIndexOf('/');
    final String directory = cut <= 0 ? '/' : path.substring(0, cut);
    final String name = path.substring(cut + 1);
    if (!await context.files.exists(directory)) {
      return null;
    }
    final List<String> backups = <String>[
      for (final String entry in await context.files.list(directory))
        if (entry.startsWith('$name.bak.')) entry,
    ]..sort();
    return backups.isEmpty ? null : '$directory/${backups.last}';
  }

  Future<void> _apply(StepContext context, String path) async {
    final Command apply = kubectl.command(<String>['apply', '-f', path]);
    final CommandResult applied = await context.shell.run(apply);
    if (!applied.ok) {
      throw CommandFailed(
        argv: apply.argv,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }
  }
}
