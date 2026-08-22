/// What the release program does, decided over a git and a set of manifests it is handed rather than
/// ones it opens inline.
///
/// Two things happen here and they are deliberately unequal. [ReleaseCommand.show] READS: it asks
/// git for the tags on the remote and for what HEAD is, reads what every package here declares, and
/// writes a screen. [ReleaseCommand.release] is the only thing in this repository that WRITES to a
/// remote, and what it pushes is a commit and one annotated tag, because
/// .github/workflows/release.yml triggers on a pushed tag and on nothing else.
///
/// THE PROGRAM'S LAST ACT IS THE PUSHED TAG. It creates no GitHub Release and writes no notes — the
/// workflow does both — so nothing here calls `gh` and nothing here checks for it.
///
/// WHICH HALF OF WHAT WAS TYPED IS WRONG IS ANSWERED, NOT LEFT TO THE READER. The channel is held
/// against [ReleaseChannel], which is what decides whether the release is a pre-release and is a
/// thing no glob can state. The version is held against the filter, by composing the tag and asking
/// it. Those are two questions and not two answers to one: a filter narrowed to two channels admits
/// a channel this program ranks, and a filter widened to a fourth admits one it does not, and each
/// of the two refusals names the file it came from. The filter is then asked a second time about a
/// probe carrying the typed channel and nothing else doubtful, which is what lets a refusal say
/// whether the version or the channel is the half that stopped it.
///
/// A FAILED READ IS NEVER AN EMPTY REMOTE. `git ls-remote` answering non-zero and a repository with
/// no tags produce the same empty list, and one of them means "nothing has been released" while the
/// other means nothing at all — so the status is read before the output is, and a failed read
/// refuses instead of proposing a first release to somebody who already released 1.4.2.
library;

import 'release_git.dart';
import 'release_packages.dart';
import 'release_report.dart';
import 'release_tag_filter.dart';
import 'release_versions.dart';

/// The release program's two acts, over a [Git] and a set of [Manifests], against one remote.
final class ReleaseCommand {
  /// Asks [git], bumps [manifests], holds what is typed against [filter], and works on [remote].
  ///
  /// [now] is the clock the ts14 half of the tag is stamped from, handed in so that a check can
  /// assert the tag a typed version and channel compose.
  const ReleaseCommand({
    required this.git,
    required this.manifests,
    required this.filter,
    this.now = DateTime.now,
    this.remote = 'origin',
  });

  /// The git the commands are run through.
  final Git git;

  /// The manifests of every package this repository releases, which a release bumps and stamps.
  final Manifests manifests;

  /// Which tags start a release, as .github/workflows/release.yml states it.
  final TagFilter filter;

  /// The clock the ts14 half of a composed tag is stamped from.
  final DateTime Function() now;

  /// The remote whose tags are the releases of these packages.
  final String remote;

  /// What has been released, what a release would carry, and what could come next — changing
  /// nothing.
  Future<ReleaseOutcome> show() async {
    if (filter.unreadable case final String why) {
      return ReleaseOutcome.refused(why);
    }
    final GitAnswer tags = await git.run(<String>['ls-remote', '--tags', remote]);
    if (!tags.isGreen) {
      return ReleaseOutcome.refused(_theTagsCouldNotBeRead(tags));
    }
    final GitAnswer branch = await git.run(<String>['rev-parse', '--abbrev-ref', 'HEAD']);
    final GitAnswer commit = await git.run(<String>['rev-parse', '--short', 'HEAD']);
    if (!branch.isGreen || !commit.isGreen) {
      return ReleaseOutcome.refused(
        'this checkout could not say which commit HEAD is at, so a release could not say what it '
        'would name — git said: ${_quoted(branch.isGreen ? commit : branch)}',
      );
    }
    return ReleaseOutcome.shown(
      listingOf(
        Releases.ofTags(tagNamesIn(tags.output), filter: filter),
        filter: filter,
        packages: ReleasedPackages.read(manifests),
        remote: remote,
        branch: _firstLineOf(branch),
        commit: _firstLineOf(commit),
      ),
    );
  }

  /// Bumps to [version], stamps the sibling refs, commits, tags and pushes — or refuses and touches
  /// nothing.
  ///
  /// The two arguments are answered before any git is run: a tag that would start nothing, or a
  /// channel nothing can rank, is refused without a network at all, and the person is told which of
  /// the two they typed was the one that stopped it.
  ///
  /// THE ORDER OF THE REFUSALS IS THE ORDER OF WHAT THEY NEED. The leading zero is asked first
  /// because it needs no file and no clock; then the channel, which needs only the ranking; then the
  /// filter, which needs the workflow read. A version wrong in more than one way is answered one
  /// reason at a time, and that order is also what keeps three refusals standing between a typed
  /// argument and `git push` rather than one.
  Future<ReleaseOutcome> release(String version, String channelName) async {
    if (numbersRefusalFor(version) case final String refusal) {
      return ReleaseOutcome.refused(refusal);
    }
    if (filter.unreadable case final String why) {
      return ReleaseOutcome.refused(why);
    }
    final ReleaseChannel? channel = ReleaseChannel.named(channelName);
    if (channel == null) {
      return ReleaseOutcome.refused(
        '"$channelName" is no channel: a release is cut on one of '
        '${ReleaseChannel.spelled.join(', ')}, as hostyour-manager/shared/release.ts:12 states '
        'them. How ripe the channel is decides whether the release page marks this a pre-release '
        'and how far the tag may then reach, and neither is a thing to guess at',
      );
    }
    // Which half of what was typed the filter stops on, told apart by a probe that varies nothing
    // but the channel: 0.0.0 carries no leading zero and fourteen zeros are fourteen digits, so a
    // probe this filter refuses is refused for its channel and for nothing else.
    if (filter.refusalFor(tagFor(version: '0.0.0', channel: channel, at: _theProbeMoment))
        case final String refusal) {
      return ReleaseOutcome.refused(
        '$releaseWorkflowPath does not trigger on the channel "$channelName", so a release cut on '
        'it would build nothing: $refusal',
      );
    }

    final String tag = tagFor(version: version, channel: channel, at: now());
    if (filter.refusalFor(tag) case final String refusal) {
      return ReleaseOutcome.refused(
        '"$version" is no version $releaseWorkflowPath triggers on — the channel "$channelName" is '
        'one it does, so the version is what stopped it: $refusal',
      );
    }

    // The manifests are read before any network, because a repository whose packages disagree about
    // what version they are at cannot be released at all and there is no reason to ask a remote
    // about it first.
    final ReleasedPackages packages = ReleasedPackages.read(manifests);
    final Bump bump = bumpFor(packages: packages, version: version, tag: tag);
    if (bump.refusal case final String why) {
      return ReleaseOutcome.refused(why);
    }

    final GitAnswer status = await git.run(<String>['status', '--porcelain']);
    if (!status.isGreen) {
      return ReleaseOutcome.refused(
        'this checkout could not say whether it is clean, and a release cut over changes nobody '
        'listed is a tree nothing in git describes — git said: ${_quoted(status)}',
      );
    }
    if (status.lines.isNotEmpty) {
      return ReleaseOutcome.refused(
        'the working tree is not clean — commit or stash first. The tag would name a commit that '
        'does not carry these changes: ${_quoted(status)}',
      );
    }

    final GitAnswer local = await git.run(<String>[
      'rev-parse',
      '-q',
      '--verify',
      'refs/tags/$tag',
    ]);
    if (local.isGreen) {
      return ReleaseOutcome.refused(
        'the tag $tag already exists in this checkout. The ts14 half of a tag is stamped from the '
        'clock, so this is a second run inside the same second or a clock that went backwards — '
        'run it again',
      );
    }
    if (local.status != 1) {
      return ReleaseOutcome.refused(
        'this checkout could not be asked whether the tag $tag already stands in it — git said: '
        '${_quoted(local)}',
      );
    }

    final GitAnswer tags = await git.run(<String>['ls-remote', '--tags', remote]);
    if (!tags.isGreen) {
      return ReleaseOutcome.refused(_theTagsCouldNotBeRead(tags));
    }
    if (Releases.ofTags(tagNamesIn(tags.output), filter: filter).holds(tag)) {
      return ReleaseOutcome.refused(
        '$tag already stands on $remote — a second tag of one name is a release nobody could tell '
        'from the first one',
      );
    }

    final (String? did, String? why) = await _write(bump, tag: tag);
    if (did == null) {
      return ReleaseOutcome.refused(why!);
    }
    final String bumped = did;

    final GitAnswer tagged = await git.run(<String>['tag', '-a', tag, '-m', tag]);
    if (!tagged.isGreen) {
      return ReleaseOutcome.refused(
        'the annotated tag $tag could not be created in this checkout, so nothing was pushed — git '
        'said: ${_quoted(tagged)}. $bumped',
      );
    }
    final GitAnswer head = await git.run(<String>['push', remote, 'HEAD']);
    if (!head.isGreen) {
      return ReleaseOutcome.refused(
        '$remote refused the commit the tag names, so the tag was not pushed either — a tag naming '
        'a commit $remote does not have is a release nothing can resolve. git said: '
        '${_quoted(head)}. $bumped, and the tag stands in this checkout; `git tag -d $tag` removes '
        'it again',
      );
    }
    final GitAnswer pushed = await git.run(<String>['push', remote, 'refs/tags/$tag']);
    if (!pushed.isGreen) {
      return ReleaseOutcome.refused(
        '$remote refused the tag $tag, so no release was started — git said: ${_quoted(pushed)}. '
        'THE COMMIT IS ALREADY ON $remote and this program does not take it back: $bumped. The tag '
        'exists in this checkout; `git tag -d $tag` removes it, and running the release again '
        'stamps a new one',
      );
    }
    return ReleaseOutcome.pushed(
      tag: tag,
      remote: remote,
      channel: channel,
      bumped: bumped,
      packages: packages.manifests.length,
    );
  }

  /// Writes what [bump] composed and commits it, answering what it did.
  ///
  /// WHAT IS STAGED IS NAMED AND NOT SWEPT. `git add --update` would stage whatever else stood
  /// changed in the tree; the working tree was found clean a moment ago, but "clean a moment ago"
  /// is not the same claim as "this commit carries these files and no others", and the second one is
  /// the one a release has to be able to make.
  ///
  /// NOTHING TO WRITE IS NOT AN ERROR AND IS NOT A COMMIT. The version half of a bump has nothing to
  /// do when the same version is cut again on a riper channel; `git commit` on an empty index
  /// refuses, and a commit forced through anyway would be a commit saying nothing. In practice the
  /// ref half always has something to do, because the ts14 makes every tag a new one — but a
  /// repository whose packages depend on none of each other has no ref half at all, and that is the
  /// tree this branch is for.
  ///
  /// The first half of the answer says what was done, or is null and the second half says why not.
  Future<(String?, String?)> _write(Bump bump, {required String tag}) async {
    if (bump.texts.isEmpty) {
      return (
        'every manifest already said what this release would write, so nothing was committed and '
            '$tag names HEAD as it stood',
        null,
      );
    }
    final String stamped = bump.stamped.isEmpty
        ? 'no package here depends on another, so no ref was stamped'
        : 'the sibling refs ${bump.stamped.join(', ')} now name $tag';
    for (final MapEntry<String, String> entry in bump.texts.entries) {
      manifests.write(entry.key, entry.value);
    }
    final List<String> written = bump.texts.keys.toList(growable: false)..sort();
    final GitAnswer staged = await git.run(<String>['add', '--', ...written]);
    if (!staged.isGreen) {
      return (
        null,
        '${written.length} manifest(s) were written and could not be staged, so nothing was '
            'committed, tagged or pushed — git said: ${_quoted(staged)}. The files are changed in '
            'this checkout; `git checkout -- ${written.join(' ')}` puts them back',
      );
    }
    final GitAnswer committed = await git.run(<String>['commit', '-m', 'release: $tag']);
    if (!committed.isGreen) {
      return (
        null,
        '${written.length} manifest(s) were written and the commit was refused, so nothing was '
            'tagged or pushed — git said: ${_quoted(committed)}. The change is staged in this '
            'checkout',
      );
    }
    return (
      '${written.length} manifest(s) were committed here as "release: $tag", and $stamped',
      null,
    );
  }

  String _theTagsCouldNotBeRead(GitAnswer answer) =>
      'the tags on $remote could not be read, so what has been released is unknown and an empty '
      'answer must not be read as an empty remote — git said: ${_quoted(answer)}';

  static String _quoted(GitAnswer answer) =>
      answer.lines.isEmpty ? '(nothing at all)' : answer.lines.join(' / ');

  static String _firstLineOf(GitAnswer answer) => answer.lines.isEmpty ? '' : answer.lines.first;

  /// The moment the channel probe is stamped at: fourteen digits that are beyond doubt, so that a
  /// refusal of the probe can only be about the channel.
  static final DateTime _theProbeMoment = DateTime.utc(2000);
}
