import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';

/// registry-completeness — [helmRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(helmRegistry);
