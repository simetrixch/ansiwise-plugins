import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_host/ansiwise_host.dart';

/// declared-answers — the probe plants what an installation plants, for [hostRegistry].
///
/// Steps of this package DO read answers, so this audit reads the installation's programs for the
/// kinds and defaults those names are declared with, and holds what the probe plants against them.
/// That is not hypothetical here: a step whose answer is declared `default: ''` is otherwise
/// reported as exercised on the placeholder text `x`, which measures a branch no installation ever
/// takes.
Future<void> main() => auditDeclaredAnswers(hostRegistry);
