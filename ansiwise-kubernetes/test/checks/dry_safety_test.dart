import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

/// dry-safety — no step of [kubernetesRegistry] can complete a mutation under `--mode dry`.
///
/// One step answers on the program row's word, and it is named below. For such a step the dry-run
/// guarantee is the row's claim and not the framework's: the row names the command and declares that
/// it only looks, and nothing here chose or verified it. The assertion is exact, so a second step
/// that takes the row's word has to be named here before this audit passes.
Future<void> main() =>
    auditDrySafety(kubernetesRegistry, answeringOnTrust: const <String>['wait_for_answer']);
