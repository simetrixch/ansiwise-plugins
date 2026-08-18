import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a pod network that overlaps something this cluster already needs to reach.
///
/// **What the overlap costs, measured on a live cluster.** A shipped default pool of `10.1.0.0/16`
/// with a cluster LAN of `10.1.1.0/24` sitting inside it: pod traffic to that LAN is routed into
/// the overlay, or leaves without being translated and the reply is swallowed by the peer's own
/// overlapping pool. Everything on the machine that dials another cluster's API server then times
/// out together — a symptom that says nothing about addressing, which is why this gate stands in
/// front of the conversion.
///
/// **Two ranges must be avoided and only one of them is this cluster's to state.** The service
/// range was fixed when the cluster was built, and the LAN is whatever this machine shares with the
/// other machines. Leaving the LAN unset skips its half of this gate, which is a choice and not an
/// oversight: a machine that shares no LAN has nothing to overlap with.
///
/// **This runs before the install and never after.** Once the pool is stamped, a check like this can
/// only report a cluster that is already broken.
final class RequirePodCidrFreeOfReservedRanges extends ObservingStep {
  /// Refuses [podCidr] when it overlaps [serviceCidr] or the answered LAN.
  const RequirePodCidrFreeOfReservedRanges({required this.podCidr, required this.serviceCidr});

  /// Builds the step from what the program gave it.
  factory RequirePodCidrFreeOfReservedRanges.fromArguments(Arguments arguments) =>
      RequirePodCidrFreeOfReservedRanges(
        podCidr: arguments.text('pod_cidr'),
        serviceCidr: arguments.text('service_cidr'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'pod_cidr',
      kind: ArgumentKind.text,
      describes: 'the address range every pod on this cluster is given an address out of',
    ),
    ArgumentSpec(
      name: 'service_cidr',
      kind: ArgumentKind.text,
      describes:
          'the range this cluster hands service addresses out of, which the pod range may not '
          'overlap — what it is was fixed when the cluster was built',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The network this machine shares with the other clusters, or empty when it shares none. That
  /// is the operator's own network and cannot be known by a program file.
  static const List<String> answers = <String>['lan_cidr'];

  /// The range every pod gets an address out of.
  final String podCidr;

  /// The range this cluster hands service addresses out of.
  final String serviceCidr;

  @override
  Future<CheckResult> check(StepContext context) async {
    // Everything wrong at once. An operator who fixes the service overlap, runs again and is then
    // told about the LAN overlap has paid for two runs to learn what one could have said.
    final List<String> problems = <String>[];

    if (!isCidr(podCidr)) {
      problems.add(
        '"$podCidr" is not an IPv4 range — it reads as an address and a prefix, such as '
        '10.244.0.0/16',
      );
    }
    if (!isCidr(serviceCidr)) {
      problems.add(
        '"$serviceCidr" is not an IPv4 range, and it is what the pod range is held against',
      );
    }
    if (context.answers.text('lan_cidr').isNotEmpty && !isCidr(context.answers.text('lan_cidr'))) {
      problems.add(
        '"${context.answers.text('lan_cidr')}" is not an IPv4 range — leave it empty when this machine shares none',
      );
    }

    if (problems.isEmpty) {
      if (cidrOverlap(podCidr, serviceCidr)) {
        problems.add(
          '$podCidr overlaps $serviceCidr, which is the range this cluster hands service '
          'addresses out of',
        );
      }
      if (context.answers.text('lan_cidr').isNotEmpty &&
          cidrOverlap(podCidr, context.answers.text('lan_cidr'))) {
        problems.add(
          '$podCidr overlaps the LAN ${context.answers.text('lan_cidr')}, and pods on it cannot reliably reach the other '
          "machines — the reply to pod traffic is swallowed by the peer's own overlapping pool",
        );
      }
    }

    if (problems.isNotEmpty) {
      return CheckResult.blocked(problems.join('; '));
    }
    if (context.answers.text('lan_cidr').isEmpty) {
      context.log.debug(
        'no LAN was given, so the pod range was only held against the service range $serviceCidr',
      );
    }
    return CheckResult.satisfied(
      '$podCidr overlaps neither $serviceCidr nor '
      '${context.answers.text('lan_cidr').isEmpty ? 'any LAN, because none was given' : context.answers.text('lan_cidr')}',
    );
  }
}
