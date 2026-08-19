import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_cloudflare/ansiwise_cloudflare.dart';

/// registry-completeness — [cloudflareRegistry] and the step classes in this tree say the same
/// thing.
void main() => auditRegistryCompleteness(cloudflareRegistry);
