import 'package:ansiwise_checks/audits.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// The declaration is `checks.yaml` beside this tree, and what it is held against is `test/checks/`:
/// the ordinary tests of this package's steps sit directly under `test/`, and only what judges the
/// package as a package is declared.
void main() => auditDeclaredChecks();
