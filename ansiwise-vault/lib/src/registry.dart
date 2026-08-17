import 'package:ansiwise_api/ansiwise_api.dart';

import 'steps/vault_auth_method.dart';
import 'steps/vault_auth_role.dart';
import 'steps/vault_init.dart';
import 'steps/vault_kv_entry.dart';
import 'steps/vault_kv_mount.dart';
import 'steps/vault_policy.dart';
import 'steps/vault_unsealed.dart';

/// Every step this plugin carries, from the names a program file writes to the classes that
/// implement them.
///
/// Written by hand, because Dart compiled ahead of time has no reflection. That is not a workaround
/// — it is what lets a check count this against the classes on disk in both directions: no step
/// exists unregistered, and no entry points at a class that is gone.
///
/// The `source` of each entry is the line its class is declared on. It is what the record reports
/// and what an operator opens when a step fails.
const Map<StepName, RegisteredStep> vaultSteps = <StepName, RegisteredStep>{
  StepName('vault_init'): RegisteredStep(
    name: StepName('vault_init'),
    source: 'lib/src/steps/vault_init.dart:33',
    create: VaultInit.fromArguments,
    arguments: VaultInit.arguments,
    answers: VaultInit.answers,
  ),
  StepName('vault_unsealed'): RegisteredStep(
    name: StepName('vault_unsealed'),
    source: 'lib/src/steps/vault_unsealed.dart:19',
    create: VaultUnsealed.fromArguments,
    arguments: VaultUnsealed.arguments,
    answers: VaultUnsealed.answers,
  ),
  StepName('vault_kv_mount'): RegisteredStep(
    name: StepName('vault_kv_mount'),
    source: 'lib/src/steps/vault_kv_mount.dart:14',
    create: VaultKvMount.fromArguments,
    arguments: VaultKvMount.arguments,
    answers: VaultKvMount.answers,
  ),
  StepName('vault_auth_method'): RegisteredStep(
    name: StepName('vault_auth_method'),
    source: 'lib/src/steps/vault_auth_method.dart:32',
    create: VaultAuthMethod.fromArguments,
    arguments: VaultAuthMethod.arguments,
    answers: VaultAuthMethod.answers,
  ),
  StepName('vault_policy'): RegisteredStep(
    name: StepName('vault_policy'),
    source: 'lib/src/steps/vault_policy.dart:33',
    create: VaultPolicy.fromArguments,
    arguments: VaultPolicy.arguments,
    answers: VaultPolicy.answers,
  ),
  StepName('vault_auth_role'): RegisteredStep(
    name: StepName('vault_auth_role'),
    source: 'lib/src/steps/vault_auth_role.dart:23',
    create: VaultAuthRole.fromArguments,
    arguments: VaultAuthRole.arguments,
    answers: VaultAuthRole.answers,
  ),
  StepName('vault_kv_entry'): RegisteredStep(
    name: StepName('vault_kv_entry'),
    source: 'lib/src/steps/vault_kv_entry.dart:28',
    create: VaultKvEntry.fromArguments,
    arguments: VaultKvEntry.arguments,
    answers: VaultKvEntry.answers,
  ),
};

/// Everything this plugin teaches the framework.
///
/// It registers no predicate: a condition is about an installation, and an installation is what
/// this package deliberately knows nothing about.
const Registry vaultRegistry = Registry(
  steps: vaultSteps,
  predicates: <PredicateName, RegisteredPredicate>{},
);
