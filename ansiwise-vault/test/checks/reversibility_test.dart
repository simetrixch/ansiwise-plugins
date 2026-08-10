import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// reversibility — every step of [vaultRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(vaultRegistry);
