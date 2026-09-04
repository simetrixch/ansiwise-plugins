import 'package:ansiwise_checks/ansiwise_checks.dart';
import 'package:ansiwise_checks/audits.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_git/ansiwise_git.dart';

/// idempotence — every step of [gitRegistry], run twice against a fake machine.
///
/// Two steps are arranged with a fixture and the rest are named in the ledger below. What decides
/// which is whether the probe's own values can reach the step at all: it hands every text argument
/// one identical character and holds an answer under that same word, so a step whose whole subject
/// is a checkout at a path its row names is refused before it does anything — unless the fake
/// machine is arranged to answer as that checkout. The two arranged here are the two that ask
/// nothing else of the machine.
Future<void> main() => auditIdempotence(
  gitRegistry,
  fixtures: stepFixtures,
  notCoveredByAFakeMachine: notCoveredByAFakeMachine,
);

/// The checkout the probe's own values point at: every text argument is [plausibleText], and the
/// answer the row's `name_answer` points at holds the same word.
const String probedCheckout = plausibleText;

/// See [probedCheckout] — the branch name, which is that same word.
const String probedBranch = plausibleText;

/// The commit the arranged remote publishes the branch on.
const String probedTip = 'a1a1a1';

/// The fake machine each named step meets, so that a second run can be measured at all.
///
/// **The effect of each command is the effect the real one has**, and no entry is registered for a
/// command that changes nothing here: a `changes` with an empty body would tell the audit that the
/// work happened while the fake machine stood exactly as it was, which is the reading the audit
/// exists to refuse.
final Map<String, Fixture> stepFixtures = <String, Fixture>{
  'git_checkout_branch': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell
      ..answers('git -C $probedCheckout rev-parse --abbrev-ref HEAD', 'somewhere-else\n')
      ..answers(
        'git -C $probedCheckout ls-remote --heads origin refs/heads/$probedBranch',
        '$probedTip\trefs/heads/$probedBranch\n',
      )
      ..answers('git -C $probedCheckout status --porcelain', '')
      ..fails('git -C $probedCheckout rev-parse --quiet --verify refs/heads/$probedBranch^{commit}')
      ..changes(
        'git -C $probedCheckout fetch origin '
        '+refs/heads/$probedBranch:refs/remotes/origin/$probedBranch',
        () => shell.answers(
          'git -C $probedCheckout rev-parse --quiet --verify '
              'refs/remotes/origin/$probedBranch^{commit}',
          '$probedTip\n',
        ),
      )
      ..changes('git -C $probedCheckout checkout -B $probedBranch origin/$probedBranch', () {
        shell
          ..answers('git -C $probedCheckout rev-parse --abbrev-ref HEAD', '$probedBranch\n')
          ..answers(
            'git -C $probedCheckout rev-parse --quiet --verify refs/heads/$probedBranch^{commit}',
            '$probedTip\n',
          );
      });
  },
  'delete_local_branch': (FakeShell shell, FakeFiles files, FakeHttp http) {
    shell
      ..answers(
        'git -C $probedCheckout rev-parse --verify --quiet refs/heads/$probedBranch',
        '$probedTip\n',
      )
      ..answers('git -C $probedCheckout rev-parse --abbrev-ref HEAD', 'somewhere-else\n')
      ..changes(
        'git -C $probedCheckout branch -D $probedBranch',
        () => shell.fails(
          'git -C $probedCheckout rev-parse --verify --quiet refs/heads/$probedBranch',
        ),
      );
  },
};

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
/// **One more arrived with the steps that moved into this package, and it is here for its own
/// measured reason** — not because the list was the quick way to make the audit green.
///
/// `stamp_placeholder_in_tracked_files` refuses for exactly the reason `git_branch` does: the value
/// it writes comes from an answer whose NAME the row chooses, and a probe holds no answers. What
/// measures it instead is test/stamp_placeholder_in_tracked_files_test.dart, which drives both of
/// its rows over a fake checkout.

const Set<String> notCoveredByAFakeMachine = <String>{
  'git_branch',
  // The two files this step reads which repository and which credential out of stand at paths its
  // row names, and the probe hands every text argument the same one-character value — so the
  // settings file is not on the fake machine and the step refuses before it ever asks git anything.
  // It is driven directly instead, over a machine that carries both files, in
  // test/git_clone_test.dart: a checkout standing on the published tip is satisfied without a
  // command that changes anything, and one that fell behind is fetched and placed.
  'git_clone',
  // Its whole question is what a REMOTE publishes, and a probe's fake machine answers a command out
  // of a fixed table — so the remote and the checkout would answer the same thing whatever the step
  // did, and running it twice would prove nothing. What measures it instead is test/git_fetch_test.dart,
  // where the checkout answers differently once the fetch has run: a second run finds the ref level
  // with what the remote publishes and asks for nothing.
  'git_fetch',
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
  // The credential it writes comes from an answer or from a file whose NAME its row chooses, and a
  // probe holds no answers and hands every text argument the same one-character value — so it is
  // handed BOTH sources at once, which the row's own shape refusal rightly rejects before this
  // machine is asked anything. What measures the same property instead is named:
  // test/git_push_credential_test.dart applies it over a fake checkout and asserts that the check
  // afterwards answers satisfied, so the second run has nothing to do.
  'git_push_credential',
  // It reads the branch a checkout stands on, and a probe hands every text argument one identical
  // value — so the path, the key and the answer's name would be that one character, and a checkout
  // that is not there refuses before anything is written. What measures it instead is
  // test/write_value_in_branch_file_test.dart, over a fake checkout: a second run finds the value
  // already recorded and has nothing to do, a file already carrying the key is edited where the line
  // stands rather than gaining a second one, and the undo puts back exactly what was there.
  'write_value_in_branch_file',
  'stamp_placeholder_in_tracked_files',
};
