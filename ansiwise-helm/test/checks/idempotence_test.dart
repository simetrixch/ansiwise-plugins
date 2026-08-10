import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [helmRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  helmRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// helm call would leave behind never sees it become true. That is not a defect in the step, and it
/// is not evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven. The list is empty because both
/// steps of this package have one.
const Set<String> notCoveredByAFakeMachine = <String>{};
