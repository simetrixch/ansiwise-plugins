import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/exchange_http_field.dart';
import 'steps/exchange_http_secret.dart';
import 'steps/measure_http_field.dart';
import 'steps/send_http_request.dart';
import 'steps/wait_for_http_field.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> httpSteps = <StepName, RegisteredStep>{
  // THE TWO EXCHANGES DIFFER IN WHAT THEY PUBLISH AND IN NOTHING ELSE. Whether a value is a
  // credential is declared in code, here, and never by a program row: a row that could say it is a
  // row that could forget to, and a credential nobody marked is one nothing hides.
  StepName('exchange_http_field'): RegisteredStep(
    name: StepName('exchange_http_field'),
    source: 'lib/src/steps/exchange_http_field.dart:23',
    create: ExchangeHttpField.fromArguments,
    arguments: ExchangeHttpField.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('http_exchanged_field'),
        describes: 'the value the named field of the answer to the one changing request holds',
      ),
    ],
  ),
  StepName('exchange_http_secret'): RegisteredStep(
    name: StepName('exchange_http_secret'),
    source: 'lib/src/steps/exchange_http_secret.dart:24',
    create: ExchangeHttpSecret.fromArguments,
    arguments: ExchangeHttpSecret.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('http_exchanged_secret'),
        describes: 'the credential the named field of the answer to the one changing request holds',
        secret: true,
      ),
    ],
  ),
  StepName('measure_http_field'): RegisteredStep(
    name: StepName('measure_http_field'),
    source: 'lib/src/steps/measure_http_field.dart:21',
    create: MeasureHttpField.fromArguments,
    arguments: MeasureHttpField.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('http_field'),
        describes: 'the value the named field of the answer holds',
      ),
    ],
  ),
  StepName('send_http_request'): RegisteredStep(
    name: StepName('send_http_request'),
    source: 'lib/src/steps/send_http_request.dart:30',
    create: SendHttpRequest.fromArguments,
    arguments: SendHttpRequest.arguments,
  ),
  StepName('wait_for_http_field'): RegisteredStep(
    name: StepName('wait_for_http_field'),
    source: 'lib/src/steps/wait_for_http_field.dart:31',
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
