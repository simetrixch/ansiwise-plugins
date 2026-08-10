import 'package:ansiwise_checks/audits.dart';

/// kubectl-composer — no step of this package puts a kubectl command line together itself.
///
/// This package holds no composer of its own. The class that knows how the client is called lives in
/// the kubernetes plugin this one depends on, and a step here that needs the cluster asks a step of
/// that plugin instead of reaching for the executable. So what this run measures is the absence: not
/// one of the step files here spells the invocation.
///
/// The exempt path is still supplied, and it names this tree's `lib/src/steps/kubectl.dart` even
/// though no such file is here. The rule is one sentence either way — every step file except the
/// composer's own — and a package that dropped the exemption would be holding a different, wider
/// rule that happens to look the same while no composer sits in its tree. The audit's counter-probe
/// drives the exemption over a tree it plants, so it is proven whether or not this tree holds one.
void main() => auditComposerPurity(executable: 'kubectl', composedIn: 'lib/src/steps/kubectl.dart');
