import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_host/ansiwise_host.dart';

/// registry-completeness — [hostRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(hostRegistry);
