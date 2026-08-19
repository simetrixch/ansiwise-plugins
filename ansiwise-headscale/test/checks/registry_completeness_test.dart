import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

/// registry-completeness — [headscaleRegistry] and the step classes in this tree say the same
/// thing.
void main() => auditRegistryCompleteness(headscaleRegistry);
