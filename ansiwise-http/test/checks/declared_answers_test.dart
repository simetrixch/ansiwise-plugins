import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_http/ansiwise_http.dart';

/// declared-answers — no registry entry of this package declares an answer, and the steps that
/// read one are told its NAME by the row.
///
/// The name is therefore a value at run time and not a constant an entry could carry, so the
/// resolver's refusal for an answer a program never declared cannot reach it. The steps refuse the
/// same case themselves, naming the answer their row pointed at.
Future<void> main() => auditDeclaredAnswers(httpRegistry);
