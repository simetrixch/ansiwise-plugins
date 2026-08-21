import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_http/ansiwise_http.dart';

/// dry-safety — no step of [httpRegistry] can complete a mutation under `--mode dry`.
///
/// The steps of this package reach their tool over the network port rather than through a shell, so
/// a mutation of theirs is a request and not a command — which is the half of the audit's
/// counter-probe that sends a POST from a plan and requires it to be refused.
///
/// No step of this package answers on the program row's word: what a row supplies is which address
/// and which field, and every request the checks send is a GET, whose harmlessness the framework
/// derives from the method itself. So the list below is empty and the assertion against it is
/// exact: a step that begins taking the row's word has to be named here before this audit passes.
Future<void> main() => auditDrySafety(httpRegistry, answeringOnTrust: const <String>[]);
