import 'package:ansiwise_checks/audits.dart';

/// exec-confinement — nothing in this package's shipped library outside `infrastructure/` reaches
/// the machine directly.
void main() => auditExecConfinement();
