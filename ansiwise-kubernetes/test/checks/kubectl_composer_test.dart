import 'package:ansiwise_checks/audits.dart';

/// kubectl-composer — one file puts every kubectl invocation together, and this keeps that true.
///
/// The composer is a file of THIS package: `lib/src/steps/kubectl.dart` holds the class that knows
/// how the client is called and how what it answers is read, and every other step here asks it
/// rather than assembling a command line of its own. That is why the exempt path below is
/// load-bearing here — spelling the executable is exactly what a composer is for, so the one file
/// that does it has to be named.
///
/// A step that spelled it too is how a value lands on a command line twice, how output parsing
/// spreads, and how the question of WHICH client runs gets answered differently in different files.
void main() => auditComposerPurity(executable: 'kubectl', composedIn: 'lib/src/steps/kubectl.dart');
