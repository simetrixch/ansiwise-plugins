import 'package:ansiwise_checks/audits.dart';

/// analysis — the analyzer and the formatter are clean over this package's own tree.
///
/// A gate walks the repository the GATE lives in, and this package is in no such repository. So
/// every package answers the two tools from its own suite, the way it answers its other checks.
void main() => auditAnalysis();
