import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';

/// idempotence — every step of [authentikRegistry], run twice against a fake machine.
///
/// **The ledger is empty, and that is a measured claim rather than an omission.** The one step here
/// changes nothing on a machine: it reads a value the run already holds, composes an address from
/// it, and publishes that. A second run over the same answers therefore composes the same address,
/// and the prober can arrange everything it needs — the answer it reads is reached through an
/// argument of the kind that names one, which a probe can plant a value for.
///
/// A name appears below only when a fake machine genuinely cannot exercise a step, and then only
/// with the reason and with what measures it instead. An empty list is the claim that no step of
/// this package needs that excuse.
Future<void> main() => auditIdempotence(
  authentikRegistry,
  fixtures: const <String, Fixture>{},
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise. None, and see above for why that is an assertion.
const Set<String> notCoveredByAFakeMachine = <String>{};
