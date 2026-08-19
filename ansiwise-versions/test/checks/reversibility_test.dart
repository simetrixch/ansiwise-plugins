import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';

/// reversibility — every step of [versionsRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(versionsRegistry);
