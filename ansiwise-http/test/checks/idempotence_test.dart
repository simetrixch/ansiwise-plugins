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
/// Empty, and that is a statement rather than an omission. No step of this package needs the fake
/// arranged: the two exchange steps are held by their KIND rather than by a fixture, for the reason
/// the ledger below gives, and the waiting step only reads.
const Map<String, Fixture> stepFixtures = <String, Fixture>{};

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers
/// nothing reads like a pass.
///
/// Empty, and the assertion against it is exact: a step this fake cannot exercise has to be named
/// here before the audit passes. A name would arrive on the day this package gains a step that
/// changes something and proves itself by reading an address again — `FakeHttp` records a request
/// and answers from a fixed table, so the request would not change what the read after it reports.
///
/// **THE TWO EXCHANGE STEPS ARE NOT HERE, AND THEY NEVER WILL BE.** Not being covered is a statement
/// about the fake, and one a fixture could one day close. An exchange is a statement about the KIND:
/// its answer is its whole effect, so a second run sends the request again on any machine, and
/// idempotence does not hold for it at all. The audit puts them in a bucket of their own, asserted
/// against the kinds the registry really builds rather than against a list kept by hand here.
const Set<String> notCoveredByAFakeMachine = <String>{};
