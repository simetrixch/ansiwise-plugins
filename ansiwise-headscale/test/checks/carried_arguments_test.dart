import 'package:ansiwise_checks/audits.dart';

/// carried-arguments — what a row grants this package's steps is carried all the way to the act.
///
/// The mirror of declared-arguments: a step that READS an argument it does not DECLARE never
/// receives the value, and a file that carries an elevation field passes it to every call it
/// governs.
void main() => auditCarriedArguments(scannedPaths: <String>['lib']);
