import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';

/// registry-completeness — [versionsRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(versionsRegistry);
