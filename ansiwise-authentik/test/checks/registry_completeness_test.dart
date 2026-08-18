import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';

/// registry-completeness — [authentikRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(authentikRegistry);
