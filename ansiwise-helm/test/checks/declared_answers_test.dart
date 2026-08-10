import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_helm/ansiwise_helm.dart';

/// declared-answers — the probe plants what an installation plants, for [helmRegistry].
///
/// Every step of this package takes what it needs as an ARGUMENT, out of the program row that names
/// it, and reads nothing out of the run — so the audit states a count of zero and opens no
/// installation tree. The day a step here reads an answer, the same audit holds that name against
/// what the programs declare for it.
Future<void> main() => auditDeclaredAnswers(helmRegistry);
