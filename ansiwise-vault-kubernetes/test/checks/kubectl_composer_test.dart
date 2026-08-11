import 'package:ansiwise_checks/audits.dart';

/// kubectl-composer — no step of this package spells a kubectl invocation of its own.
///
/// **The composer is not in this tree, and the rule is the same anyway.** `Kubectl` lives in the
/// cluster package, at the path named below, and that is the one file allowed to spell how the
/// client is invoked. The step here asks it, exactly as every step of the cluster package does, so
/// the exempt path names a file this scan will never meet and every step file of this tree is held
/// to "spells it nowhere".
///
/// It is the second package that reaches a cluster, which is precisely why it needs this check: a
/// step that assembled its own command line here would answer the question of WHICH client runs
/// differently from every step next door, and the two would only disagree on a machine where the
/// client is wrapped.
void main() => auditComposerPurity(executable: 'kubectl', composedIn: 'lib/src/steps/kubectl.dart');
