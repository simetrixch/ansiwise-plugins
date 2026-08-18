import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';

/// reversibility — every step of [authentikRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(authentikRegistry);
