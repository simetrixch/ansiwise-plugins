import 'package:ansiwise_api/ansiwise_api.dart';
import 'registry/branch.dart';
import 'registry/cluster.dart';
import 'registry/gitops.dart';

/// The map from the names a program file writes to the classes that implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection. That is not a workaround
/// — it is what lets a check count this against the classes on disk **in both directions**: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails, so the same check verifies that the file exists and
/// declares that class at that line. A number nobody checks drifts within a week.
///
/// Composed from one map per area. An area is added by writing its file and naming it here, which is
/// the only line two people writing two areas both touch.
const Registry executionRegistry = Registry(
  steps: <StepName, RegisteredStep>{...branchSteps, ...clusterSteps, ...gitopsSteps},
  predicates: <PredicateName, RegisteredPredicate>{...gitopsPredicates},
);
