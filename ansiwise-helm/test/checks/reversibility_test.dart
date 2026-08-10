import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';

/// reversibility — every step of [helmRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(helmRegistry);
