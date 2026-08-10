import 'package:ansiwise_checks/audits.dart';

/// exec-confinement — nothing in this package's shipped library outside `infrastructure/` reaches
/// the machine directly.
///
/// The tree is this package's own, for the same reason case-sensitivity's is: a scan rooted at the
/// product that composes these steps holds none of their files.
void main() => auditExecConfinement();
