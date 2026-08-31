import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [headscaleRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  headscaleRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
const Set<String> notCoveredByAFakeMachine = <String>{
  // Where the credential goes comes EITHER from the path the row writes OR from an answer whose
  // name the row chooses, and a probe hands every declared argument a value — so it is handed both
  // sources at once, which the row's own shape refusal rightly rejects before the coordinator is
  // asked anything. The fixture beside this file still arranges the coordinator, and it is not the
  // coordinator that stops the probe.
  //
  // What measures the same property instead is named: test/tailnet_join_credential_test.dart holds
  // a coordinator that still redeems the standing credential and asserts the check answers
  // satisfied with no create among the commands run — which is exactly what this audit asks of a
  // second run — and beside it the answered path is applied and read back where the run said.
  'tailnet_join_credential',
};
