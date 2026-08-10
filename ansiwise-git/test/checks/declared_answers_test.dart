import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_git/ansiwise_git.dart';

/// declared-answers — the probe plants what an installation plants, for [gitRegistry].
///
/// No entry of this registry declares an answer, so the audit states a count of zero and opens no
/// installation tree.
///
/// **One step of this package does read an answer, and this is where that is said out loud.**
/// `git_branch` is told by its row WHICH answer holds the branch name, so the name it reaches for is
/// a value at run time rather than a constant an entry could carry — there is nothing here for this
/// audit to hold against a program's declaration. What that costs is the resolver's refusal for an
/// answer a program never declared: it cannot reach that step, so the step refuses the same case
/// itself, at check time, naming the answer its row pointed at. Whoever composes this package into a
/// product is the one who can declare the name statically, and that is where the refusal before the
/// run belongs.
Future<void> main() => auditDeclaredAnswers(gitRegistry);
