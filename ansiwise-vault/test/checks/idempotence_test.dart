import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// idempotence — every step of [vaultRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  vaultRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The fake machine each named step meets, by the name a program file writes.
///
/// Empty, and that is a statement rather than an omission. Every step of this package but one
/// reaches Vault over HTTP, and `FakeHttp` answers a request without the request before it having
/// changed what it answers — there is no arrangement of it under which a POST makes the following
/// GET report the new state. The one exception writes onto a cluster as well, and a fixture cannot
/// close that one either: what stops it is not the fake but the VALUES the audit hands the step,
/// which a fixture does not get to choose. Its `fields` argument arrives as the audit's generic
/// text, that text is not a `key=field` pair, and the step refuses before it writes anything. So no
/// fixture here could take a step out of the ledger below, and every one of them stands in it as
/// unproven.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// Every step of this package but one reaches Vault over HTTP: it asks what the tool holds, and it
/// posts what the tool should hold. `FakeHttp` records a request and answers from a fixed table, so
/// a POST does not change what the GET after it reports, and the second check reads exactly what the
/// first one did. The exception is the step that materializes an entry onto a cluster, and it is
/// unexercised for the different reason stated above: the audit hands it a `fields` value that is
/// not a `key=field` pair, so its apply refuses instead of running.
///
/// None of that is a defect in the step, and none of it is evidence that the step is idempotent —
/// so all of them stand here, and this whole package's idempotence rests on the tests beside this
/// directory rather than on this audit.
///
/// A name leaves this list on the day a fake network can be arranged to answer differently after a
/// request that changed something, the way `FakeShell.changes` already does for a command.
const Set<String> notCoveredByAFakeMachine = <String>{
  'kubernetes_secret_from_vault',
  'vault_auth_method',
  'vault_auth_role',
  'vault_init',
  'vault_kv_entry',
  'vault_kv_mount',
  'vault_policy',
  'vault_unsealed',
};
