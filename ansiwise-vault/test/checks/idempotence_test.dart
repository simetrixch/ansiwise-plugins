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
/// Empty, and that is a statement rather than an omission. Every step of this package reaches Vault
/// over HTTP, and `FakeHttp` answers a request without the request before it having changed what it
/// answers — there is no arrangement of it under which a POST makes the following GET report the new
/// state. So no fixture here could take a step out of the ledger below, and every one of them stands
/// in it as unproven.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// Every step of this package reaches Vault over HTTP: it asks what the tool holds, and it posts
/// what the tool should hold. `FakeHttp` records a request and answers from a fixed table, so a POST
/// does not change what the GET after it reports, and the second check reads exactly what the first
/// one did.
///
/// That is not a defect in the steps, and it is no evidence that they are idempotent — so all of
/// them stand here, and this whole package's idempotence rests on the tests beside this directory
/// rather than on this audit.
///
/// A name leaves this list on the day a fake network can be arranged to answer differently after a
/// request that changed something, the way `FakeShell.changes` already does for a command.
const Set<String> notCoveredByAFakeMachine = <String>{
  'file_from_vault',
  'remove_vault_auth_method',
  'remove_vault_kv_entry',
  'remove_vault_policy',
  'vault_auth_method',
  'vault_auth_role',
  'vault_init',
  'vault_kv_entry',
  'vault_kv_mount',
  'vault_kv_ssh_key_pair',
  'vault_policy',
  'vault_unsealed',
};
