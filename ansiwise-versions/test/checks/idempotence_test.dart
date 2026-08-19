import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';

/// idempotence — every step of [versionsRegistry], run twice against a fake machine.
///
/// No step of this package is arranged with a fixture, and none of them could be: both read the
/// checkouts through a trees mapping whose labels a probe cannot line up with the declaration
/// tree it also invents, so each refuses before it reaches a file — and a refusal measures the
/// probe, not the step.
Future<void> main() => auditIdempotence(
  versionsRegistry,
  fixtures: const <String, Fixture>{},
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers
/// nothing reads like a pass.
///
/// `stamp_version_pins` refuses under probe for the reason above: the probe binds one invented
/// tree label while the row's declaration tree is another invented word, so the check blocks
/// before any file is read, and what a second run would do was measured by nothing here. **What
/// measures it instead is named, rather than left as a gap:** test/stamp_version_pins_test.dart
/// runs the same step against a fake machine holding a declaration and its target files, applies
/// it, and asserts that the check afterwards answers satisfied and that a second run has nothing
/// left to write — the same property this audit measures, proven where the files can be arranged.
///
/// `report_version_pins_against_upstream` only measures, and under probe it answers the same
/// refusal twice, so the audit already covers what it can. It stands here regardless because the
/// answer it repeats is a refusal about the probe's trees rather than a reading of any upstream;
/// what measures the reporting itself is test/report_version_pins_against_upstream_test.dart,
/// over a fake network that serves each kind of feed.
///
/// A name leaves this list by gaining a fixture in a fixtures map that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{'stamp_version_pins'};
