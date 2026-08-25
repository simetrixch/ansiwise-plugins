/// A `capture` has no "more work" direction. Everywhere else a refusal folded into "the thing
/// is missing" makes the step Ready and the work happens, and the cost is one unnecessary apply.
/// Here every value is an instruction to the `undo`: one half leaves a thing alone, the other
/// takes it away. Three captures of this tree answered a cluster's exit code, which is one for a
/// cluster that does not hold the object AND for a cluster that could not be asked - and that
/// false half was the half the undo deleted on.
library;

import 'package:ansiwise_checks_tree/audits.dart';

void main() => auditCapturedRefusal(scannedPaths: <String>['lib']);
