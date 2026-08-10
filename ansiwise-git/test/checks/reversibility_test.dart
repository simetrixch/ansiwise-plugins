import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_git/ansiwise_git.dart';

/// reversibility — every step of [gitRegistry] answers "can this be taken back", and an
/// irreversible one says what is lost.
void main() => auditReversibility(gitRegistry);
