import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

import 'step_fixtures.dart';

/// idempotence — every step of [executionRegistry], run twice against a fake machine.
///
/// The answers are every one the installation's programs declare, so each step meets the kind and
/// the default a real run would give it rather than a placeholder.
Future<void> main() async => auditIdempotence(
  executionRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
  answers: await plausibleAnswers(const RealFiles(), installationProgramsRoot),
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// A `FakeShell` records a command and does not carry it out, so a step whose postcondition a real
/// `snap install`, `helm upgrade` or `kubectl apply` would leave behind never sees it become true; a
/// step whose precondition is a checkout, an account or a running cluster is blocked before it
/// starts. Neither is a defect in the step, and neither is evidence that it is idempotent.
///
/// A name leaves this list by gaining a fixture in step_fixtures.dart that arranges the fake machine
/// for it. A name arrives here only by somebody adding it, which is the point: a step written
/// tomorrow either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{
  'configure_kube_apiserver_oidc',
  'restart_microk8s_snap_for_pod_cidr',
  // Nothing about the fake machine keeps it from being exercised: the ANSWERS do, and no fixture can
  // reach them. A probe plants a value for every declared answer independently, and "role" and
  // "master" are two declarations — so what it plants is a cluster that holds the master part AND
  // names another one, which is exactly the pair this step now refuses. It used to be reported as
  // exercised because it refused only the other half and read the second answer nowhere, which is
  // the defect that was fixed. Closing this needs a declaration that can state a relationship
  // between two answers; it is the same reason write_cluster_map stands below.
  'stamp_cluster_profile',
  'stamp_placeholder_in_tracked_files',
  'stamp_role',
  'write_cluster_map',
};
