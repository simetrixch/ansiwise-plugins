import 'package:ansiwise_core/ansiwise_core.dart';

import 'steps/file_from_vault.dart';
import 'steps/measure_vault_url.dart';
import 'steps/remove_vault_auth_method.dart';
import 'steps/remove_vault_kv_entry.dart';
import 'steps/remove_vault_policy.dart';
import 'steps/remove_vault_role_member.dart';
import 'steps/vault_auth_method.dart';
import 'steps/vault_auth_role.dart';
import 'steps/vault_init.dart';
import 'steps/vault_kv_entry.dart';
import 'steps/vault_kv_mount.dart';
import 'steps/vault_login_probe.dart';
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
    source: 'lib/src/steps/vault_auth_method.dart:34',
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
  StepName('file_from_vault'): RegisteredStep(
    name: StepName('file_from_vault'),
    source: 'lib/src/steps/file_from_vault.dart:26',
    create: FileFromVault.fromArguments,
    arguments: FileFromVault.arguments,
  ),
  // The one step of this family that hands something OUT rather than writing something in: the
  // address the profile records, published so that a row of another package — a wait, a gate — can
  // be pointed at the same Vault the rows around it talk to. It declares no answer of its own, for
  // the reason the entries above give.
  StepName('measure_vault_url'): RegisteredStep(
    name: StepName('measure_vault_url'),
    source: 'lib/src/steps/measure_vault_url.dart:26',
    create: MeasureVaultUrl.fromArguments,
    arguments: MeasureVaultUrl.arguments,
    publishes: <MeasurementSpec>[
      MeasurementSpec(
        name: MeasurementName('vault_url'),
        describes: "the address this installation's Vault answers at, as its profile records it",
      ),
    ],
  ),
  // The gate that proves a mount's connection to its cluster with a real login attempt. Which
  // answer holds the credential it presents is the row's to say, so no answer is declared here.
  StepName('vault_login_probe'): RegisteredStep(
    name: StepName('vault_login_probe'),
    source: 'lib/src/steps/vault_login_probe.dart:29',
    create: VaultLoginProbe.fromArguments,
    arguments: VaultLoginProbe.arguments,
  ),
  // The four removal steps, for taking one cluster's surface off a Vault that serves several. Each
  // proves absence rather than assuming it, and each spells its target with the same slots the
  // writing rows used.
  StepName('remove_vault_policy'): RegisteredStep(
    name: StepName('remove_vault_policy'),
    source: 'lib/src/steps/remove_vault_policy.dart:18',
    create: RemoveVaultPolicy.fromArguments,
    arguments: RemoveVaultPolicy.arguments,
  ),
  StepName('remove_vault_auth_method'): RegisteredStep(
    name: StepName('remove_vault_auth_method'),
    source: 'lib/src/steps/remove_vault_auth_method.dart:19',
    create: RemoveVaultAuthMethod.fromArguments,
    arguments: RemoveVaultAuthMethod.arguments,
  ),
  StepName('remove_vault_kv_entry'): RegisteredStep(
    name: StepName('remove_vault_kv_entry'),
    source: 'lib/src/steps/remove_vault_kv_entry.dart:18',
    create: RemoveVaultKvEntry.fromArguments,
    arguments: RemoveVaultKvEntry.arguments,
  ),
  StepName('remove_vault_role_member'): RegisteredStep(
    name: StepName('remove_vault_role_member'),
    source: 'lib/src/steps/remove_vault_role_member.dart:19',
    create: RemoveVaultRoleMember.fromArguments,
    arguments: RemoveVaultRoleMember.arguments,
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
