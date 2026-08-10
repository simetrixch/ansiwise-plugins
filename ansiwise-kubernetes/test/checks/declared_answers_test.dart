import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';

/// declared-answers — the probe plants what an installation plants, for [kubernetesRegistry].
///
/// Steps of this package DO read answers, so this audit reads the installation's programs for the
/// kinds and defaults those names are declared with, and holds what the probe plants against them. A
/// probe that invented a value would exercise a branch no installation takes while the branch every
/// installation does take was measured by nothing.
Future<void> main() => auditDeclaredAnswers(kubernetesRegistry);
