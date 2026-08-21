import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_http/ansiwise_http.dart';

/// idempotence — every step of [httpRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  httpRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The fake machine each named step meets, by the name a program file writes.
///
/// Empty, and that is a statement rather than an omission. The mutating step of this package speaks
/// over HTTP, and `FakeHttp` answers a request without the request before it having changed what it
/// answers — there is no arrangement of it under which the sent request makes the read after it
/// report the new state. So no fixture here could take that step out of the ledger below.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers
/// nothing reads like a pass.
///
/// The mutating step sends what its row composes and proves itself by reading the row's own
/// already-address again. `FakeHttp` records a request and answers from a fixed table, so the
/// request does not change what the read after it reports, and the second check reads exactly what
/// the first one did.
///
/// That is not a defect in the step, and it is no evidence that it is idempotent — so it stands
/// here, and its idempotence rests on the test beside this directory, which scripts a network that
/// answers differently once the request has been sent.
///
/// A name leaves this list on the day a fake network can be arranged to answer differently after a
/// request that changed something, the way `FakeShell.changes` already does for a command.
///
/// **THE TWO EXCHANGE STEPS ARE NOT HERE, AND THEY NEVER WILL BE.** Not being covered is a statement
/// about the fake, and one a fixture could one day close. An exchange is a statement about the KIND:
/// its answer is its whole effect, so a second run sends the request again on any machine, and
/// idempotence does not hold for it at all. The audit puts them in a bucket of their own, asserted
/// against the kinds the registry really builds rather than against a list kept by hand here.
const Set<String> notCoveredByAFakeMachine = <String>{'send_http_request'};
