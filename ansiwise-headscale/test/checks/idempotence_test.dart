import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [headscaleRegistry], run twice against a fake machine.
Future<void> main() => auditIdempotence(
  headscaleRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise. Empty: the one step here is covered by its fixture —
/// the fake coordinator answers its listings, the create flips the key listing to redeemable the
/// way a real coordinator's state does, and the second run finds the credential standing and does
/// nothing.
const Set<String> notCoveredByAFakeMachine = <String>{};
