/// What a person reads when they run tool/release.dart, what the release page says, and the one line
/// that says what the run did.
///
/// The text is here rather than written where the work happens, so a check can assert what a person
/// sees without a git, a remote or a terminal — a screen nothing can read is a screen nobody can
/// hold to anything.
///
/// A RELEASE HERE CARRIES NO FILE, AND THE PAGE HAS TO SAY SO. These packages compile to nothing:
/// they are libraries, nobody downloads them, and every consumer resolves them as a git dependency.
/// So the tree at the tag IS the artefact, and what a release page is for is telling a consumer the
/// two words it now writes into its own pubspec — the ref, which is the tag, and the path, which is
/// the package it wants.
library;

import 'release_packages.dart';
import 'release_tag_filter.dart';
import 'release_versions.dart';

/// What one invocation of the release program did.
final class ReleaseOutcome {
  /// [text] is everything the person reads, and [isGreen] whether the run did what it was asked.
  const ReleaseOutcome({required this.text, required this.isGreen});

  /// Nothing was done, and [why] says what was wrong.
  factory ReleaseOutcome.refused(String why) =>
      ReleaseOutcome(text: 'release: FAIL — $why', isGreen: false);

  /// [listing] was shown and nothing was touched.
  factory ReleaseOutcome.shown(String listing) => ReleaseOutcome(
    text:
        '$listing\n'
        'release: OK — nothing was pushed; a release starts when a version and a channel are typed',
    isGreen: true,
  );

  /// The tag [tag] was pushed to [remote], which is the whole of what starts a release.
  ///
  /// [bumped] says what happened to the manifests, because a person who typed a version has to know
  /// what was committed in their name before the tag was put on it.
  factory ReleaseOutcome.pushed({
    required String tag,
    required String remote,
    required ReleaseChannel channel,
    required String bumped,
    required int packages,
  }) => ReleaseOutcome(
    text:
        'release: OK — the tag $tag is on $remote, and pushing it is the whole of what starts a '
        'release\n'
        '  $bumped\n'
        '  $releaseWorkflowPath runs the gate over every package of this repository and then\n'
        '  creates a GitHub Release named $tag,\n'
        '  ${channel.isPreRelease ? 'marked as a pre-release because ${channel.name} is not the ripest channel' : 'published plainly, because ${channel.name} is the ripest channel'}\n'
        '  gh run watch --repo simetrixch/ansiwise-plugins   follows it\n'
        '  THE RELEASE CARRIES NO FILE: these $packages package(s) compile to nothing, and the tree\n'
        '  at $tag is what a consumer resolves. The release page lists the ref and the path each\n'
        '  package is named by\n'
        '  THE CHANNEL IS A CEILING, NOT A DEPLOYMENT: ${channel.name} reaches ${channel.reaches}.\n'
        '  Nothing in this repository enforces that ceiling — it is enforced where deployments\n'
        '  are written (hostyour-manager/shared/release.ts:8)\n'
        '  NO CONSUMER HAS IT YET: a consumer resolves what its own pubspec.yaml names, and this\n'
        '  release did not touch any consumer. Until one names $tag as its ref it still resolves\n'
        '  whatever its ref says today',
    isGreen: true,
  );

  /// Everything the person reads.
  final String text;

  /// Whether the run did what it was asked.
  final bool isGreen;
}

/// What one run of the notes program produced: the page, or the reason there is none.
final class NotesOutcome {
  /// [page] is what the release page carries, and [isPreRelease] how the release is to be marked.
  const NotesOutcome.written({required this.page, required this.isPreRelease}) : refusal = null;

  /// Nothing was written, and [refusal] says what could not be read.
  const NotesOutcome.refused(this.refusal) : page = '', isPreRelease = false;

  /// What the release page carries.
  final String page;

  /// Whether the release is to be marked as a pre-release.
  final bool isPreRelease;

  /// Why there is no page, or null when there is one.
  final String? refusal;

  /// Whether the run did what it was asked.
  bool get isGreen => refusal == null;
}

/// The page a GitHub Release named by [release]'s tag carries.
///
/// [previous] is the release this one follows, or null when it is the first, and [subjects] are the
/// commit subjects between the two. AN EMPTY RANGE IS SAID OUT LOUD rather than left as a heading
/// with nothing under it: a release whose tag names the same commit as the last one is a real thing
/// — the same code cut on a riper channel — and a page that simply showed no changes would read as a
/// page nobody generated.
///
/// [packages] is what stands in the tree at this tag, so the page lists what it really carries
/// rather than what was there when somebody last edited this file. [url] is the address this
/// repository's own packages name it by, and it is copied out of the tree for the same reason: pub
/// treats two spellings of one address as two sources, so a page inventing a second spelling would
/// hand a consumer a pubspec that cannot resolve beside the lines it already has.
String notesFor({
  required ReleasedTag release,
  required ReleaseChannel channel,
  required String? previous,
  required List<String> subjects,
  required List<ManifestState> packages,
  required String? url,
}) {
  final StringBuffer page = StringBuffer()
    ..writeln('Channel **${channel.name}** — this release may run in ${channel.reaches}.')
    ..writeln('')
    ..writeln(
      'The ceiling is enforced where deployments are written, not by this release '
      '(hostyour-manager/shared/release.ts:8).',
    )
    ..writeln('')
    ..writeln('## What this release is')
    ..writeln('')
    ..writeln(
      'Nothing is attached below, and nothing is missing. These ${packages.length} package(s) are '
      'libraries: they compile to no file and nobody downloads one. The tree at `${release.tag}` is '
      'the release, and a consumer takes it by naming that tag as the `ref` of a git dependency.',
    )
    ..writeln('')
    ..writeln('## What a consumer writes')
    ..writeln('')
    ..writeln('```yaml')
    ..writeln('dependencies:');
  for (final ManifestState package in packages) {
    page
      ..writeln('  ${package.declaredName ?? package.directory}:')
      ..writeln('    git:')
      ..writeln(url == null ? '      url: <this repository>' : '      url: $url')
      ..writeln('      ref: ${release.tag}')
      ..writeln('      path: ${package.directory}');
  }
  page
    ..writeln('```')
    ..writeln('')
    ..writeln(
      'Every package of this repository is at ${release.version} in this release, and one ref '
      'serves all of them: a git dependency names a ref and a path, so a consumer picks the '
      'packages it wants out of the one tag. Two packages of this repository held at two different '
      'refs is a tree pub refuses to resolve.',
    )
    ..writeln('')
    ..writeln(
      previous == null
          ? '## Changes — every commit up to this tag, because nothing was released before it'
          : '## Changes since $previous',
    )
    ..writeln('');
  if (subjects.isEmpty) {
    page.writeln(
      previous == null
          ? 'No commit was found behind this tag, which is a history nobody could read.'
          : 'Nothing changed since $previous: this tag names the same code, cut again.',
    );
  }
  for (final String subject in subjects) {
    page.writeln('- $subject');
  }
  if (previous != null) {
    page
      ..writeln('')
      ..writeln('`git log --format=%s $previous..${release.tag}` is the range this was read from.');
  }
  return page.toString();
}

/// The screen shown when the program is run with no arguments: what the workflow releases on, what
/// has been released, what a tag would name, what it would carry, what it still follows a branch of,
/// and what could come next.
///
/// [branch] and [commit] describe what HEAD is, because the tag a release pushes names THIS commit —
/// a person deciding a version is deciding which commit becomes a release, and a screen that hid it
/// would hide half the decision.
///
/// WHAT IS FOLLOWED IS SHOWN BESIDE WHAT COULD COME NEXT, because the two are read together. The
/// proposals below are versions a person may type, and while a dependency on another repository
/// names a branch none of them can be cut at all — a screen offering them with nothing said would be
/// offering a release this program is about to refuse.
String listingOf(
  Releases releases, {
  required TagFilter filter,
  required ReleasedPackages packages,
  required String remote,
  required String branch,
  required String commit,
}) {
  final StringBuffer screen = StringBuffer()
    ..writeln('a tag starts a release when $releaseWorkflowPath triggers on it, which is:');
  for (final String pattern in filter.stated) {
    screen.writeln('  $pattern');
  }
  screen
    ..writeln('')
    ..writeln('one tag carries every package of this repository, each at its own path:');
  for (final ManifestState package in packages.manifests) {
    screen.writeln(
      '  ${package.directory.padRight(26)}${package.declaredName ?? '(no name declared)'} '
      '${package.declaredVersion ?? '(no version declared)'}',
    );
  }
  if (packages.refusal case final String why) {
    screen
      ..writeln('')
      ..writeln('and they cannot be released as they stand:')
      ..writeln('  $why');
  }
  screen
    ..writeln('')
    ..writeln(
      'what these packages follow rather than pin, which stops a release before it starts:',
    );
  final List<String> followed = packages.followed(filter);
  if (followed.isEmpty) {
    screen.writeln('  nothing — every dependency on another repository names a released tag');
  }
  for (final String following in followed) {
    screen.writeln('  $following');
  }
  screen
    ..writeln('')
    ..writeln('released so far, read from the tags on $remote:');
  if (releases.releases.isEmpty) {
    screen.writeln('  nothing — no version of these packages has been released');
  } else {
    for (final ReleasedTag released in releases.releases.reversed) {
      screen.writeln('  ${released.tag}');
    }
  }
  if (releases.otherTags.isNotEmpty) {
    screen
      ..writeln('')
      ..writeln('tags on $remote this screen could not place as a release:');
    for (final String tag in releases.otherTags) {
      screen.writeln('  $tag');
    }
  }
  screen
    ..writeln('')
    ..writeln('a release would name this commit:')
    ..writeln('  $branch at $commit')
    ..writeln('')
    ..writeln('possible next versions, none of them chosen:');
  final List<Proposal> proposals = releases.proposals(declaredVersion: packages.declaredVersion);
  if (proposals.isEmpty) {
    screen.writeln('  none — no version is declared here to offer as the first release');
  }
  for (final Proposal proposal in proposals) {
    screen.writeln('  ${proposal.version.padRight(16)}${proposal.because}');
  }
  screen
    ..writeln('')
    ..writeln('and the channel, which is a ceiling on where the tag may run:');
  for (final ReleaseChannel channel in ReleaseChannel.values) {
    screen.writeln('  ${channel.name.padRight(16)}reaches ${channel.reaches}');
  }
  screen
    ..writeln('')
    ..writeln('type the version and the channel you decided on:')
    ..writeln('  dart run tool/release.dart <version> <channel>')
    ..writeln('  dart run tool/release.dart help     what a release is, and what it is not');
  return screen.toString();
}

/// What `help` writes.
///
/// IT DOES NOT SPELL OUT WHICH TAGS ARE ADMITTED. The one place that decides is `on.push.tags` in
/// the workflow; the program reads it every run and the screen prints what it says today, so a help
/// text carrying its own copy would be a second spelling of it.
const String helpText = '''
release — show what has been released, and start a release of a version and a channel you type.

  dart run tool/release.dart                        what has been released, and what could come next
  dart run tool/release.dart <version> <channel>    push the tag, which starts the release
  dart run tool/release.dart help                   this

WHAT A RELEASE OF THESE PACKAGES IS. They are libraries and they compile to nothing, so a release
attaches no file: it is a TAG, and the tree at that tag is what a consumer resolves. Today every
consumer names these packages at `ref: master`, which means a push reaches all of them at once and
nobody decided that it should. A consumer pins the tag instead, and then a push reaches nobody until
somebody moves that pin.

ONE TAG CARRIES EVERY PACKAGE HERE. A git dependency names a ref and a path, so one ref serves all
of them and each consumer picks the paths it wants. Two packages of this repository held at two
different refs is a tree pub refuses to resolve, which is why there is one tag and not one per
package.

WITH NO ARGUMENTS IT CHANGES NOTHING. It reads the tags on origin, prints what has been released,
lists every package the tag would carry and the version each declares, names the commit a release
would carry, lists every dependency on another repository that still names a branch, and proposes
what could come next. It never picks a version: which release a change deserves is a decision, and a
program that took it would hide it.

WHAT THE TWO ARGUMENTS COMPOSE. The tag is <major>.<minor>.<patch>-<channel>-<ts14>, where the ts14
is the UTC yyyyMMddHHmmss this program stamps at the moment you run it — never typed, which is what
makes one version cut twice on one channel two tags instead of one name pushed twice. The grammar is
hostyour-manager/shared/release.ts:22, one grammar for every release of everything.

THE CHANNEL IS A CEILING ON WHERE THE TAG MAY RUN — alpha reaches dev, beta reaches dev and test, stable
reaches everywhere — and NOTHING HERE ENFORCES IT. It is enforced where deployments are written
(hostyour-manager/shared/release.ts:8). What the channel decides here is only whether the release
page marks the release as a pre-release.

WHAT HAPPENS WHEN YOU TYPE THEM. The working tree has to be clean and every package here has to
declare the same version. Two things are then written into the manifests and committed as one:
every package's version is set to the one you typed, and every dependency one package of this
repository declares on another has its `ref:` stamped to the tag being cut — a tag whose inside
still said `master` would pin nothing. An ANNOTATED tag is created on that commit, HEAD is pushed
and the tag is pushed, and that is all that happens here.

WHAT IS NOT STAMPED AND STOPS THE RELEASE INSTEAD. A dependency on ANOTHER repository — the
framework, the audits — is left exactly as it stands, because the tag being cut is a name in THIS
repository and writing it there would name a tag that repository does not have. So such a ref has to
already name a released tag, and while one names a branch the release refuses and lists every line
to put right. Pinning them is an edit in this repository, made before the release is run.

WHAT DOES NOT HAPPEN. No release is created here — the workflow runs the gate over every package,
creates the release, writes its notes and marks a pre-release. And no consumer gets anything: a
consumer resolves what its own pubspec.yaml names, and moving that pin is a separate act in a
separate repository.
''';
