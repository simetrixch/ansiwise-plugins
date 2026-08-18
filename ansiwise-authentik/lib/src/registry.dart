import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/measure_issuer_url.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> authentikSteps = <StepName, RegisteredStep>{
  StepName('measure_issuer_url'): RegisteredStep(
    name: StepName('measure_issuer_url'),
    source: 'lib/src/steps/measure_issuer_url.dart:22',
    create: MeasureIssuerUrl.fromArguments,
    arguments: MeasureIssuerUrl.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('issuer_url'),
        describes: 'the address the named application\'s tokens are issued at',
      ),
    ],
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about one product's state, and that is what this
/// package deliberately knows nothing about.
const Registry authentikRegistry = Registry(
  steps: authentikSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
