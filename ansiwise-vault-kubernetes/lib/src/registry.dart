import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/kubernetes_secret_from_vault.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection. That is not a workaround
/// — it is what lets a check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
///
/// **The step name is the one the program rows already write.** What moved is which package the
/// class is compiled out of, and a program file names a step rather than a package — so a rename
/// here would break every row for a change no row can see.
const Map<StepName, RegisteredStep> vaultKubernetesSteps = <StepName, RegisteredStep>{
  // It reads no answer by a name of its own. The one axis a product may run the same layout along
  // more than once is named by the row under `run_answer`, exactly as it is for every step of the
  // vault family, so this entry declares none and the slot in the entry path is filled from that
  // name.
  StepName('kubernetes_secret_from_vault'): RegisteredStep(
    name: StepName('kubernetes_secret_from_vault'),
    source: 'lib/src/steps/kubernetes_secret_from_vault.dart:50',
    create: KubernetesSecretFromVault.fromArguments,
    arguments: KubernetesSecretFromVault.arguments,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about an installation, and an installation is what
/// this package deliberately knows nothing about.
const Registry vaultKubernetesRegistry = Registry(
  steps: vaultKubernetesSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
