import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// registry-completeness — [vaultRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(vaultRegistry);
