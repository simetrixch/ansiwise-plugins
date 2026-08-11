import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';

/// registry-completeness — [vaultKubernetesRegistry] and the step classes in this tree say the same
/// thing.
void main() => auditRegistryCompleteness(vaultKubernetesRegistry);
