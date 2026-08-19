import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

/// reversibility — every step of [headscaleRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(headscaleRegistry);
