import 'package:ansiwise_checks/audits.dart';

/// case-sensitivity — every directive of THIS package's tree spells the on-disk name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step in this plugin runs against and the machine the binary is compiled for.
///
/// THE TREE IS THIS PACKAGE'S OWN, AND EVERY OTHER PACKAGE RUNS THE SAME AUDIT OVER ITS OWN. The
/// five tool packages this plugin stands on are a DEPENDENCY here, resolved from a pin or a checkout
/// beside this one, so not one of their files is a path of this tree — a scan rooted here would step
/// past every step they ship and report a clean answer over code it never opened.
void main() => auditCaseSensitivity();
