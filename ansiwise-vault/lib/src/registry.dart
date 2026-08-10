import 'package:ansiwise_api/ansiwise_api.dart';

import 'steps/vault_auth_method.dart';
import 'steps/vault_auth_role.dart';
import 'steps/vault_init.dart';
import 'steps/vault_kv_entry.dart';
import 'steps/vault_kv_mount.dart';
import 'steps/vault_policy.dart';
import 'steps/vault_unsealed.dart';

/// Every step this plugin contributes, keyed by the name a program file writes.
///
/// The composition root of a binary spreads this map into its own registry, beside the maps of the
/// other plugins it compiles in.
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
    source: 'lib/src/steps/vault_auth_method.dart:22',
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
