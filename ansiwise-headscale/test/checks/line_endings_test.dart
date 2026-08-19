import 'package:ansiwise_checks/audits.dart';

/// line-endings — every file THIS package declares as LF is LF in the working copy too.
void main() => auditLineEndings();
