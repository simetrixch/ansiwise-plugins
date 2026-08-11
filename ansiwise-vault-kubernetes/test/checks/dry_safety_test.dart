import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';

/// dry-safety — no step of [vaultKubernetesRegistry] can complete a mutation under `--mode dry`.
///
/// The step of this package reaches BOTH tools: it reads the store over HTTP and writes to the
/// cluster through a command, so both halves of the audit's counter-probe bear on it — the one that
/// sends a POST from a plan and the one that runs a mutating command from a plan, each required to
/// be refused.
///
/// No step of this package answers on the program row's word, so the list below is empty and the
/// assertion against it is exact: a step that begins taking the row's word has to be named here
/// before this audit passes.
Future<void> main() => auditDrySafety(vaultKubernetesRegistry, answeringOnTrust: const <String>[]);
