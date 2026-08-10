import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_host/ansiwise_host.dart';

/// reversibility — every step of [hostRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(hostRegistry);
