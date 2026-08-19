import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';

/// reversibility — every step of [cloudflareRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
///
/// Every step here is reversible on purpose: each one reads the record slot it is about to change
/// BEFORE it changes it, and its undo writes back exactly what was read — or removes the one record
/// the step itself created. The tests beside this directory drive both directions.
void main() => auditReversibility(cloudflareRegistry);
