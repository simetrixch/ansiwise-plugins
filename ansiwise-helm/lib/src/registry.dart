import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/helm_release.dart';
import 'steps/helm_repository.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection, which is what lets a
/// check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> helmSteps = <StepName, RegisteredStep>{
  StepName('helm_repository'): RegisteredStep(
    name: StepName('helm_repository'),
    source: 'lib/src/steps/helm_repository.dart:16',
    create: HelmRepository.fromArguments,
    arguments: HelmRepository.arguments,
  ),
  StepName('helm_release'): RegisteredStep(
    name: StepName('helm_release'),
    source: 'lib/src/steps/helm_release.dart:21',
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
