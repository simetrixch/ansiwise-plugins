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
/// **Three more arrived with the steps that moved into this package, and each is here for its own
/// measured reason** — not because the list was the quick way to make the audit green.
///
/// `stamp_placeholder_in_tracked_files` refuses for exactly the reason `git_branch` does: the value
/// it writes comes from an answer whose NAME the row chooses, and a probe holds no answers. What
/// measures it instead is test/stamp_placeholder_in_tracked_files_test.dart, which drives both of
/// its rows over a fake checkout.
///
/// `replace_regex_in_tracked_file` is blocked before it starts, because the file it is told to
/// modify has to exist and a probe hands it a one-character path.
///
/// `replace_text_in_tracked_files` is the other shape and the worse one: the fake machine ALREADY
/// satisfies it — the probe's placeholder is in no file, so there is no work and the step never goes
/// from having some to having none. **Nothing else measures these last two**, and that is stated
/// here rather than left to be discovered: they came out of the dissolved package without a test of
/// their own.
const Set<String> notCoveredByAFakeMachine = <String>{
  'git_branch',
  'replace_regex_in_tracked_file',
  'replace_text_in_tracked_files',
  'stamp_placeholder_in_tracked_files',
};
