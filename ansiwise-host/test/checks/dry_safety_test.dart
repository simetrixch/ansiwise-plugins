import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_host/ansiwise_host.dart';

/// dry-safety — no step of [hostRegistry] can complete a mutation under `--mode dry`.
///
/// No step of this package answers on the program row's word, so the list below is empty and the
/// assertion against it is exact: a step that begins taking the row's word has to be named here
/// before this audit passes, because for such a step the dry-run guarantee is the row's claim rather
/// than the framework's.
Future<void> main() => auditDrySafety(hostRegistry, answeringOnTrust: const <String>[]);
