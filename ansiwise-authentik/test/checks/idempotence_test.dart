import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';

/// idempotence — every step of [authentikRegistry], run twice against a fake machine.
///
/// One name stands in the ledger, and the reason is a property of this audit rather than of the
/// step. The audit answers a request out of a FIXED TABLE: a table does not change because
/// something was posted to it, so the second check reads exactly what the first one did and a run
/// over a step that talks to the provider proves nothing at all.
///
/// The other two need no excuse. Neither changes anything on a machine — one composes an address
/// out of a value the run already holds, the other asks the provider one read-only question — so a
/// second run over the same machine answers exactly what the first one answered, which is the whole
/// of what this audit asks of a step that only measures.
///
/// A name appears below only when a fake machine genuinely cannot exercise a step, and then only
/// with the reason and with what measures it instead.
Future<void> main() => auditIdempotence(
  authentikRegistry,
  fixtures: const <String, Fixture>{},
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers
/// nothing reads like a pass.
///
/// What measures this one instead: test/group_membership_test.dart, whose provider KEEPS ITS STATE
/// — what is added to the group is what the next query answers — so "the second run has nothing
/// left to do" is a measured claim there rather than an artefact of a table that never moves.
const Set<String> notCoveredByAFakeMachine = <String>{'authentik_group_membership'};
