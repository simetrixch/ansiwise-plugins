import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// dry-safety — no step of [vaultRegistry] can complete a mutation under `--mode dry`.
///
/// The steps of this package reach their tool over HTTP rather than through a shell, so a mutation
/// of theirs is a request and not a command — which is the half of the audit's counter-probe that
/// sends a POST from a plan and requires it to be refused.
///
/// No step of this package answers on the program row's word, so the list below is empty and the
/// assertion against it is exact: a step that begins taking the row's word has to be named here
/// before this audit passes.
Future<void> main() => auditDrySafety(vaultRegistry, answeringOnTrust: const <String>[]);
