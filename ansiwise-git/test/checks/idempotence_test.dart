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
  // The two files this step reads which repository and which credential out of stand at paths its
  // row names, and the probe hands every text argument the same one-character value — so the
  // settings file is not on the fake machine and the step refuses before it ever asks git anything.
  // It is driven directly instead, over a machine that carries both files, in
  // test/git_clone_test.dart: a checkout standing on the published tip is satisfied without a
  // command that changes anything, and one that fell behind is fetched and placed.
  'git_clone',
  // Both for the reason git_branch is here: each reads a name out of an answer its row chooses —
  // the branch being brought forward, the commit measured for it — and a probe holds no answers, so
  // each refuses before it merges or copies anything. What measures them instead is named:
  // test/git_merge_ref_test.dart drives the merge over a fake checkout, up to and including a
  // second run finding the commit already among the ancestors; test/copy_branch_file_test.dart
  // does the same for the copy, whose second run finds the destination already holding the source.
  'copy_branch_file',
  'git_merge_ref',
  // For exactly the reason above: both values come from answers whose NAMES the row chooses, and a
  // probe holds none — so it would measure the step against a run that knows nothing, which is not
  // the act the step performs. test/git_identity_test.dart drives it over a fake checkout: applied
  // twice the second run has nothing to do, and the undo puts back the identity that stood there
  // rather than taking away one somebody set for their own reasons.
  'git_identity',
  // Both for the reason above, one level on: they read a checkout the probe cannot arrange. A probe
  // holds no answers and hands every text argument one identical value, so the paths a commit names
  // and the remote a push sends to are the same one-character string — and a checkout that is not
  // there refuses before either does anything. They are driven directly instead, over a fake
  // checkout that answers the way a healthy one does, in test/git_deliver_test.dart: a second commit
  // records nothing and does not fail for it, and a push whose branch the remote already carries at
  // the same commit is satisfied before it sends.
  'git_commit',
  'git_push',
  // The same shape once more, and the reason is the checkout rather than the answers: a probe hands
  // every text argument one identical value, so the tag, the ref and the remote would all be that
  // one character — and a checkout that is not there refuses before anything is tagged. What
  // measures it instead is test/git_tag_test.dart, over a fake checkout that answers the way a real
  // one does: a second run finds the tag already on the same commit here AND on the remote and asks
  // for nothing, a tag standing on another commit is refused rather than moved, and the undo takes
  // back only a tag this run made.
  'git_tag',
  // The credential it writes comes from an answer or from a file whose NAME its row chooses, and a
  // probe holds no answers and hands every text argument the same one-character value — so it is
  // handed BOTH sources at once, which the row's own shape refusal rightly rejects before this
  // machine is asked anything. What measures the same property instead is named:
  // test/git_push_credential_test.dart applies it over a fake checkout and asserts that the check
  // afterwards answers satisfied, so the second run has nothing to do.
  'git_push_credential',
  'replace_regex_in_tracked_file',
  'replace_text_in_tracked_files',
  'stamp_placeholder_in_tracked_files',
};
