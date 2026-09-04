import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/report_version_pins_against_upstream.dart';
import 'steps/stamp_version_pins.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
///
/// **No entry declares an answer, and both steps read them.** Each row maps the declaration's tree
/// labels to checkouts, and a binding may name WHICH answer holds a checkout's path — so the names
/// are values at run time, not constants a registry entry could carry. The resolver's refusal for
/// an answer a program never declared therefore cannot reach these steps, and each refuses the
/// same case itself, naming the answer its row pointed at.
const Map<StepName, RegisteredStep> versionsSteps = <StepName, RegisteredStep>{
  StepName('stamp_version_pins'): RegisteredStep(
    name: StepName('stamp_version_pins'),
    source: 'lib/src/steps/stamp_version_pins.dart:31',
    create: StampVersionPins.fromArguments,
    arguments: StampVersionPins.arguments,
  ),
  StepName('report_version_pins_against_upstream'): RegisteredStep(
    name: StepName('report_version_pins_against_upstream'),
    source: 'lib/src/steps/report_version_pins_against_upstream.dart:32',
    create: ReportVersionPinsAgainstUpstream.fromArguments,
    arguments: ReportVersionPinsAgainstUpstream.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about one product's state, and that is what this
/// package deliberately knows nothing about.
const Registry versionsRegistry = Registry(
  steps: versionsSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
