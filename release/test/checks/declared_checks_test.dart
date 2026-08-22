import 'package:ansiwise_checks_tree/audits.dart';

/// declared-checks — this package is told what it checks, and holds the disk against it.
///
/// The declaration is `checks.yaml` beside this tree, and what it is held against is `test/checks/`.
void main() => auditDeclaredChecks();
