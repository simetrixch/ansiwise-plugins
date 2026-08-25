import 'package:ansiwise_core/ansiwise_core.dart';
import 'kubectl.dart';

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
final class RemoveDefaultIpv4Ippool extends IrreversibleStep {
  /// Deletes the pool unless it already carries [podCidr], with [manifestPath] as the proof of order.
  const RemoveDefaultIpv4Ippool({
    required this.podCidr,
    required this.manifestPath,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory RemoveDefaultIpv4Ippool.fromArguments(Arguments arguments) => RemoveDefaultIpv4Ippool(
    podCidr: arguments.text('pod_cidr'),
    manifestPath: arguments.text('manifest_path'),
    kubectl: Kubectl.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
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
          'before the pool may go — where that file sits is a fact about the installation',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The pool Calico creates from the shipped manifest, and the only one this program touches.
  static const String poolName = 'default-ipv4-ippool';

  /// The range the pool the cluster is running on covers, null when there is no pool, or why
  /// neither could be read.
  ///
  /// **This is the live source of truth for the whole conversion, and the manifest is not.** The
  /// manifest's value is consumed once at creation, so a machine can carry a correctly stamped
  /// manifest and still run on the old pool. Every convergence question in this phase is asked here.
  ///
  /// A cluster that could not be asked used to come back as the same null a cluster with no pool
  /// does, and the check below answered "there is no $poolName, so there is none to delete" over it
  /// — a row that ships immediately after the cluster comes up, which is exactly when an API server
  /// does not answer. The pod-network conversion then silently did not happen and the row stood
  /// proven. See [Kubectl.readOne] for how the two are told apart.
  static Future<({String? cidr, String? refusal})> liveCidr(
    StepContext context,
    Kubectl kubectl,
  ) async {
    final ({String? answer, String? refusal}) pool = await kubectl.readOne(
      context,
      kind: 'ippool',
      name: poolName,
      output: 'jsonpath={.spec.cidr}',
    );
    if (pool.refusal case final String refusal) {
      return (cidr: null, refusal: refusal);
    }
    final String? cidr = pool.answer?.trim();
    return (cidr: cidr == null || cidr.isEmpty ? null : cidr, refusal: null);
  }

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The manifest the pool is built again from.
  final String manifestPath;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  String get irreversibleReason =>
      'the address pool a running cluster is using is gone, and every pod holding an address out of '
      'it keeps that address with nothing routing to it — what is lost is state nothing wrote down, '
      'and only recreating each of those pods gives them an address again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final ({String? cidr, String? refusal}) reading = await liveCidr(context, kubectl);
    if (reading.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final String? live = reading.cidr;
    if (live == null) {
      return const CheckResult.satisfied('there is no $poolName, so there is none to delete');
    }
    if (live == podCidr) {
      return CheckResult.satisfied('$poolName already covers $podCidr');
    }

    // The order of this phase, enforced where getting it wrong is invisible. Deleting first means
    // Calico builds the pool again from a manifest that still names the old range, the cluster
    // converges on the value the conversion exists to leave behind, and every step reports success.
    if (!await context.files.exists(manifestPath, elevated: elevated)) {
      return CheckResult.blocked(
        '$manifestPath is not there, and it is what Calico builds the pool again from — deleting '
        'now would leave the cluster with no pool at all',
      );
    }
    final String manifest = await context.files.read(manifestPath, elevated: elevated);
    if (!manifest.contains(podCidr)) {
      return CheckResult.blocked(
        '$manifestPath does not carry $podCidr yet, and Calico builds the pool again from that '
        'file — deleting now would bring the pool straight back on $live',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(kubectl.argv(_delete));

  @override
  Future<void> apply(StepContext context) async {
    await delete(context, kubectl);
  }

  /// Deletes the pool, and fails when the command does.
  ///
  /// Shared with the verify step, whose self-heal is this same delete taken a second time when a
  /// startup race put the pool back on the old range.
  static Future<void> delete(StepContext context, Kubectl kubectl) async {
    final Command command = kubectl.command(_delete);
    final CommandResult deleted = await context.shell.run(command);
    if (!deleted.ok) {
      throw CommandFailed(
        argv: command.argv,
        exitCode: deleted.exitCode,
        stdout: '',
        stderr: deleted.stderr,
      );
    }
  }

  /// What deletes the pool, after the words the client is invoked with.
  static const List<String> _delete = <String>['delete', 'ippool', poolName];
}
