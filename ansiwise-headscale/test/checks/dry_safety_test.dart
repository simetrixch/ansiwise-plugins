import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_headscale/ansiwise_headscale.dart';

/// dry-safety — no step of [headscaleRegistry] can complete a mutation under `--mode dry`.
///
/// The step of this package asks the coordinator through commands and writes the credential file,
/// so both a mutating command and a file write from a plan are what the counter-probe requires to
/// be refused. No step here answers on the program row's word, so the list below is empty and the
/// assertion against it is exact.
Future<void> main() => auditDrySafety(headscaleRegistry, answeringOnTrust: const <String>[]);
