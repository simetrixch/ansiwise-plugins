import 'package:ansiwise_api/ansiwise_api.dart';
import 'stamp_calico_pool_cidr_in_cni_manifest.dart';

/// Deletes the address pool the cluster is running on, so Calico builds it again on the new range.
///
/// **This is the primary path and not an edge case.** Even a machine that was installed minutes ago
/// already has a pool: Calico creates it from the shipped manifest the first time it starts. Treating
/// the delete as something that only applies to an existing cluster leaves a fresh install on the
/// shipped default, with every step reporting success.
///
/// **Calico never mutates a pool that exists.** The range in the manifest is read once, at creation,
/// so changing the manifest does nothing to the pool that is already there. Deleting it is what lets
/// the range take effect, and it is why the manifest has to carry the new range BEFORE this runs —
/// otherwise the pool comes straight back on the old one. That order is a precondition here rather
/// than a comment somewhere: this refuses to delete against an unstamped manifest.
final class DeleteDefaultIpv4Ippool extends IrreversibleStep {
  /// Deletes the pool unless it already carries [podCidr], with [manifestPath] as the proof of order.
  const DeleteDefaultIpv4Ippool({required this.podCidr, required this.manifestPath});

  /// Builds the step from what the program gave it.
  factory DeleteDefaultIpv4Ippool.fromArguments(Arguments arguments) => DeleteDefaultIpv4Ippool(
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
      describes:
          'the network manifest Calico builds the pool again from, which must carry the range '
          'before the pool may go',
      required: false,
      defaultValue: StampCalicoPoolCidrInCniManifest.defaultPath,
    ),
  ];

  /// The pool MicroK8s ships, and the only one this program touches.
  static const String poolName = 'default-ipv4-ippool';

  /// The range the pool the cluster is running on covers, or null when there is no pool.
  ///
  /// **This is the live source of truth for the whole conversion, and the manifest is not.** The
  /// manifest's value is consumed once at creation, so a machine can carry a correctly stamped
  /// manifest and still run on the old pool. Every convergence question in this phase is asked here.
  static Future<String?> liveCidr(StepContext context) async {
    final CommandResult pool = await context.shell.run(
      const Command.observing('microk8s', <String>[
        'kubectl',
        'get',
        'ippool',
        poolName,
        '-o',
        'jsonpath={.spec.cidr}',
      ]),
    );
    if (!pool.ok || pool.trimmed.isEmpty) {
      return null;
    }
    return pool.trimmed;
  }

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The manifest the pool is built again from.
  final String manifestPath;

  @override
  String get irreversibleReason =>
      'the address pool a running cluster is using is gone, and every pod holding an address out of '
      'it keeps that address with nothing routing to it — what is lost is state nothing wrote down, '
      'and only recreating each of those pods gives them an address again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? live = await liveCidr(context);
    if (live == null) {
      return const CheckResult.satisfied('there is no $poolName, so there is none to delete');
    }
    if (live == podCidr) {
      return CheckResult.satisfied('$poolName already covers $podCidr');
    }

    // The order of this phase, enforced where getting it wrong is invisible. Deleting first means
    // Calico builds the pool again from a manifest that still names the old range, the cluster
    // converges on the value the conversion exists to leave behind, and every step reports success.
    if (!await context.files.exists(manifestPath)) {
      return CheckResult.blocked(
        '$manifestPath is not there, and it is what Calico builds the pool again from — deleting '
        'now would leave the cluster with no pool at all',
      );
    }
    final String manifest = await context.files.read(manifestPath);
    if (!manifest.contains(podCidr)) {
      return CheckResult.blocked(
        '$manifestPath does not carry $podCidr yet, and Calico builds the pool again from that '
        'file — deleting now would bring the pool straight back on $live',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(argv);

  @override
  Future<void> apply(StepContext context) async {
    await delete(context);
  }

  /// Deletes the pool, and fails when the command does.
  ///
  /// Shared with the verify step, whose self-heal is this same delete taken a second time when a
  /// startup race put the pool back on the old range.
  static Future<void> delete(StepContext context) async {
    final CommandResult deleted = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!deleted.ok) {
      throw CommandFailed(argv: argv, exitCode: deleted.exitCode, stderr: deleted.stderr);
    }
  }

  /// The command that deletes the pool.
  static const List<String> argv = <String>['microk8s', 'kubectl', 'delete', 'ippool', poolName];
}
