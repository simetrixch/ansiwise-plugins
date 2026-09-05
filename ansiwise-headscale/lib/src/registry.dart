import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/remove_tailnet_user.dart';
import 'steps/tailnet_join_credential.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection, which is what lets a
/// check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> headscaleSteps = <StepName, RegisteredStep>{
  // It reads no answer by a name of its own: which answer holds the machine's name at the
  // coordinator, and which one fills the marked slot in the invocation, are both said by the row —
  // so this entry declares none, the way the whole package carries no name of any one product.
  StepName('tailnet_join_credential'): RegisteredStep(
    name: StepName('tailnet_join_credential'),
    source: 'lib/src/steps/tailnet_join_credential.dart:29',
    create: TailnetJoinCredential.fromArguments,
    arguments: TailnetJoinCredential.arguments,
  ),
  // The mint's inverse, under the same doctrine: which answer holds the machine's name at the
  // coordinator, and which one fills the marked slot in the invocation, are both said by the row —
  // so this entry declares no answer of its own either.
  StepName('remove_tailnet_user'): RegisteredStep(
    name: StepName('remove_tailnet_user'),
    source: 'lib/src/steps/remove_tailnet_user.dart:24',
    create: RemoveTailnetUser.fromArguments,
    arguments: RemoveTailnetUser.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about an installation, and an installation is what
/// this package deliberately knows nothing about.
const Registry headscaleRegistry = Registry(
  steps: headscaleSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
