import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

/// declared-answers — the probe plants what an installation plants, for [headscaleRegistry].
///
/// No step of this package reads an answer by a name of its own: which answer holds the machine's
/// name at the coordinator is the row's to say, under `user_answer`, so the registry declares none
/// and the audit asserts that nothing was planted for nobody.
Future<void> main() => auditDeclaredAnswers(headscaleRegistry);
