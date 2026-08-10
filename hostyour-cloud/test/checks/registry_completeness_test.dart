import 'package:ansiwise_checks/audits.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

/// registry-completeness — [executionRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(executionRegistry);
