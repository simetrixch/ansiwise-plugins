import 'package:ansiwise_checks/audits.dart';

/// line-endings — every file THIS package declares as LF is LF in the working copy too.
///
/// The gate judges the working copy rather than a fresh checkout, so a file with CRLF here is a file
/// with CRLF in everything built from it.
void main() => auditLineEndings();
