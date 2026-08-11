import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault_kubernetes/ansiwise_vault_kubernetes.dart';

/// reversibility — every step of [vaultKubernetesRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(vaultKubernetesRegistry);
