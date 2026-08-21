import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_http/ansiwise_http.dart';

/// registry-completeness — [httpRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(httpRegistry);
