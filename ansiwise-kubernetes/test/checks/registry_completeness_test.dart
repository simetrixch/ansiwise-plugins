import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

/// registry-completeness — [kubernetesRegistry] and the step classes in this tree say the same
/// thing.
void main() => auditRegistryCompleteness(kubernetesRegistry);
