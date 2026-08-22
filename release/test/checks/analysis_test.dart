import 'package:ansiwise_checks_tree/audits.dart';

/// analysis — the analyzer and the formatter are clean over this package's own tree.
///
/// The release program is Dart like everything else here, and it is held to the same rule set: a
/// program that decides what reaches a remote must not be the one tree nobody analysed.
void main() => auditAnalysis();
