import 'package:ansiwise_checks/audits.dart';

/// refused-reading — this package's steps never answer SATISFIED on a reading that was refused.
///
/// A reading that COULD NOT BE TAKEN turned into an answer is the shape that cost this platform
/// three outages: "the tool did not answer" comes back looking exactly like "there is nothing
/// there". The refusal is followed from the branch it opens, through every bare value it is folded
/// into, to the `CheckResult.satisfied` it reaches — because in the measurement that cost eight
/// satisfied rows the refused command sat two declarations away from the claim.
void main() => auditRefusedReading(scannedPaths: <String>['lib']);
