import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_git/ansiwise_git.dart';

/// registry-completeness — [gitRegistry] and the step classes in this tree say the same thing.
void main() => auditRegistryCompleteness(gitRegistry);
