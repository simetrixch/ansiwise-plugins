import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_git/ansiwise_git.dart';

/// idempotence — every step of [gitRegistry], run twice against a fake machine.
///
/// No step of this package is arranged with a fixture, and none of them could be: the two gates only
/// measure, so a fake answers them the same way twice without any arrangement, and the one step that
/// changes something is named in the ledger below for a reason no arrangement of a fake shell
/// reaches.
Future<void> main() => auditIdempotence(
  gitRegistry,
  fixtures: const <String, Fixture>{},
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The steps a fake machine cannot exercise, each named because an audit that quietly covers nothing
/// reads like a pass.
///
/// `git_branch` reads the branch name out of an answer its row names, and a probe holds no answers
/// at all — it can plant a value for a name a registry entry declares, and this entry declares none
/// because the name is the row's to choose. So the step refuses before it ever cuts anything, and
/// what a second run would do was measured by nothing here.
///
/// **What measures it instead is named, rather than left as a gap:** test/git_branch_test.dart runs
/// the same step against a fake machine that holds the answer, applies it, and asserts that the
/// check afterwards answers satisfied and that a second run runs no command at all. That is the
/// same property this audit measures, proven where the answer can be arranged.
///
/// A name leaves this list by gaining a fixture in a fixtures map that arranges the fake machine for
/// it. A name arrives here only by somebody adding it, which is the point: a step written tomorrow
/// either brings its fixture or is written down as unproven.
const Set<String> notCoveredByAFakeMachine = <String>{'git_branch'};
