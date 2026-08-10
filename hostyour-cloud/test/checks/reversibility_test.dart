import 'package:ansiwise_checks/audits.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

/// reversibility — every step of [executionRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(executionRegistry);
