import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';

import '../composition.dart';

/// dry-safety — no step the BINARY composes can complete a mutation under `--mode dry`.
///
/// The registry here is the shipped one and not this package's own. What an operator installs is
/// five plugins, and a dry-run guarantee measured over one of them says nothing about the other four
/// — the deployment's programs name `wait_for_answer` three times, and it is a step whose answer
/// rests on the row's word. Measured here, that fact is stated; measured over this package alone,
/// the list below would be empty and the suite would read as though nothing took the row's word.
///
/// The answers are every one the installation's programs declare, rather than only the ones this
/// registry's steps read: the product owns the programs and registers the steps of every plugin
/// under it, so there is no name among them that belongs to nobody.
Future<void> main() async => auditDrySafety(
  await shippedRegistry(),
  answeringOnTrust: const <String>['wait_for_answer'],
  answers: await plausibleAnswers(const RealFiles(), installationProgramsRoot),
);
