import 'package:ansiwise_checks/audits.dart';

/// case-sensitivity — every directive of THIS package's tree spells the on-disk name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step of this package runs against and the machine the binary is compiled for.
void main() => auditCaseSensitivity();
