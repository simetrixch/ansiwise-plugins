import 'package:ansiwise_checks/audits.dart';

/// case-sensitivity — every directive of THIS package's tree spells the on-disk name byte for byte.
///
/// `import 'Foo.dart'` for a file named `foo.dart` compiles on Windows and fails on Linux, which is
/// the machine every step of this package runs against and the machine the binary is compiled for.
///
/// THE TREE IS THIS PACKAGE'S OWN. A scan rooted at the product that composes these steps would not
/// see one file of this package: its sources are a dependency there, resolved from a pin or a
/// checkout, and neither is a path of that tree. So every package runs the same audit over the tree
/// it is, and [auditCaseSensitivity] takes the repository this suite runs in.
void main() => auditCaseSensitivity();
