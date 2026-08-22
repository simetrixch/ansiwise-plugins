import 'package:ansiwise_checks_tree/audits.dart';

/// line-endings — every file this package declares as LF is LF in the working copy too.
///
/// The suite judges the working copy rather than a fresh checkout, so a file with CRLF here is a
/// file with CRLF in everything read from it.
void main() => auditLineEndings();
