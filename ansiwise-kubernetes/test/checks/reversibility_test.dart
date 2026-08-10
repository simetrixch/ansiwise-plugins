import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

/// reversibility — every step of [kubernetesRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(kubernetesRegistry);
