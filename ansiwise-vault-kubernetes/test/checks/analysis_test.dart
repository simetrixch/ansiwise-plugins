import 'package:ansiwise_checks/audits.dart';

/// analysis — the analyzer and the formatter are clean over this package's own tree.
///
/// The two tools used to run over the packages of one repository, because a gate walks the
/// repository the GATE lives in and this package is in no such repository. So every package
/// answers them from its own suite, the way it answers its other checks.
void main() => auditAnalysis();
