import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';

/// idempotence — every step of [vaultKubernetesRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  vaultKubernetesRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The fake machine each named step meets, by the name a program file writes.
///
/// Empty, and that is a statement rather than an omission. What stops the one step here is not the
/// fake but the VALUES the audit hands it, which a fixture does not get to choose: its `fields`
/// argument arrives as the audit's generic text, that text is not a `key=field` pair, and the step
/// refuses before it writes anything. So no fixture here could take the step out of the ledger
/// below.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// The step reads the store over HTTP and writes to the cluster through a command. It is
/// unexercised here for the reason stated above — the generic `fields` text the audit hands it is
/// not a `key=field` pair — and it would be unexercised even with a fixture, because `FakeHttp`
/// answers a request without the request before it having changed what it answers, so a second read
/// reports exactly what the first one did.
///
/// Neither of those is a defect in the step, and neither is evidence that the step is idempotent —
/// so it stands here, and this package's idempotence rests on the test beside this directory rather
/// than on this audit. That test applies the step against a fake machine holding a real
/// `key=field` list, and asserts what the second run would find: the check answers satisfied once
/// the Secret stands, so nothing is written again.
///
/// A name leaves this list on the day the audit hands a step values a program row would give it,
/// and a fake network can be arranged to answer differently after a request that changed something
/// — the way `FakeShell.changes` already does for a command.
const Set<String> notCoveredByAFakeMachine = <String>{'kubernetes_secret_from_vault'};
