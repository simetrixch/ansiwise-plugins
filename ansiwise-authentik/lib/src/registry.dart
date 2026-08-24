import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/group_membership.dart';
import 'steps/measure_issuer_url.dart';
import 'steps/report_out_of_box_flow.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> authentikSteps = <StepName, RegisteredStep>{
  StepName('authentik_group_membership'): RegisteredStep(
    name: StepName('authentik_group_membership'),
    source: 'lib/src/steps/group_membership.dart:26',
    create: GroupMembership.fromArguments,
    arguments: GroupMembership.arguments,
  ),
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
  StepName('report_out_of_box_flow'): RegisteredStep(
    name: StepName('report_out_of_box_flow'),
    source: 'lib/src/steps/report_out_of_box_flow.dart:36',
    create: ReportOutOfBoxFlow.fromArguments,
    arguments: ReportOutOfBoxFlow.arguments,
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
