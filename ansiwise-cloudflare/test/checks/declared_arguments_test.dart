import 'package:ansiwise_checks/audits.dart';

/// declared-arguments — every argument this package declares is one something reads.
///
/// The quiet half of a pair. A row naming an argument the step does NOT declare is refused by name;
/// one naming an argument the step declares and never reads is accepted, ignored, and reported as
/// success. Both shapes it catches happened in this tree on one day.
void main() => auditDeclaredArguments(scannedPaths: <String>['lib']);
