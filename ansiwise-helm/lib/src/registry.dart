import 'package:ansiwise_api/ansiwise_api.dart';

import 'steps/helm_release.dart';
import 'steps/helm_repository.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
const Map<StepName, RegisteredStep> helmSteps = <StepName, RegisteredStep>{
  StepName('helm_repository'): RegisteredStep(
    name: StepName('helm_repository'),
    source: 'lib/src/steps/helm_repository.dart:14',
    create: HelmRepository.fromArguments,
    arguments: HelmRepository.arguments,
  ),
  StepName('helm_release'): RegisteredStep(
    name: StepName('helm_release'),
    source: 'lib/src/steps/helm_release.dart:18',
    create: HelmRelease.fromArguments,
    arguments: HelmRelease.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about an installation, and an installation is what
/// this package deliberately knows nothing about.
const Registry helmRegistry = Registry(
  steps: helmSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
