import 'package:ansiwise_checks_tree/audits.dart';

/// case-sensitivity — every directive of this package spells the on-disk name byte for byte.
///
/// This tree is edited on Windows and run on a Linux runner. A directive whose case does not match
/// the file opens here and finds nothing there, and the release would fail in the job that publishes
/// it rather than in the one a person watched.
void main() => auditCaseSensitivity();
