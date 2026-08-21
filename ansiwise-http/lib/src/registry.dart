import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/read_http_field.dart';
import 'steps/send_http_request.dart';
import 'steps/wait_for_http_field.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> httpSteps = <StepName, RegisteredStep>{
  StepName('read_http_field'): RegisteredStep(
    name: StepName('read_http_field'),
    source: 'lib/src/steps/read_http_field.dart:21',
    create: ReadHttpField.fromArguments,
    arguments: ReadHttpField.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('http_field'),
        describes: 'the value the named field of the answer holds',
      ),
    ],
  ),
  StepName('send_http_request'): RegisteredStep(
    name: StepName('send_http_request'),
    source: 'lib/src/steps/send_http_request.dart:24',
    create: SendHttpRequest.fromArguments,
    arguments: SendHttpRequest.arguments,
  ),
  StepName('wait_for_http_field'): RegisteredStep(
    name: StepName('wait_for_http_field'),
    source: 'lib/src/steps/wait_for_http_field.dart:22',
    create: WaitForHttpField.fromArguments,
    arguments: WaitForHttpField.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about one product's state, and that is what this
/// package deliberately knows nothing about.
const Registry httpRegistry = Registry(
  steps: httpSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
