import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_authentik/ansiwise_authentik.dart';

/// declared-answers — no registry entry of this package declares an answer, and every step that
/// reads one is told its NAME by the row.
///
/// The name is therefore a value at run time and not a constant an entry could carry, so the
/// resolver's refusal for an answer a program never declared cannot reach any of them. Each such
/// step refuses the same case itself, naming the answer its row pointed at.
Future<void> main() => auditDeclaredAnswers(authentikRegistry);
