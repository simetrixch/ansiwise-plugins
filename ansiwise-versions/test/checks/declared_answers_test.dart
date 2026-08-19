import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_versions/ansiwise_versions.dart';

/// declared-answers — the probe plants what an installation plants, for [versionsRegistry].
///
/// No entry of this registry declares an answer, so the audit states a count of zero and opens no
/// installation tree.
///
/// **Both steps of this package do read answers, and this is where that is said out loud.** Each
/// row's trees mapping may bind a tree label to the NAME of the answer holding that checkout's
/// path, so the names are values at run time rather than constants an entry could carry — there is
/// nothing here for this audit to hold against a program's declaration. What that costs is the
/// resolver's refusal for an answer a program never declared: it cannot reach these steps, so each
/// refuses the same case itself, at check time, naming the answer its row pointed at. Whoever
/// composes this package into a product is the one who can declare the names statically, and that
/// is where the refusal before the run belongs.
Future<void> main() => auditDeclaredAnswers(versionsRegistry);
