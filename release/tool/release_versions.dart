/// What a release tag is made of, what order releases stand in, and what could be released next.
///
/// A release of this repository IS a tag on origin: .github/workflows/release.yml triggers on a
/// pushed tag and on nothing else, and the GitHub Release it then creates is named by that tag. So
/// the tags are what is read, and WHICH OF THEM STARTS A RELEASE IS ASKED OF THE [TagFilter] read
/// from that workflow — never decided here.
///
/// THE TAG IS `<major>.<minor>.<patch>-<channel>-<ts14>`, one grammar for every release of
/// everything, and the file that owns it is hostyour-manager/shared/release.ts:22. The ts14 is the
/// UTC moment the tag was composed at, which is what makes two releases of one version on one
/// channel two tags instead of one name pushed twice.
///
/// WHAT THIS FILE STATES THAT NO FILTER COULD, and why that is not a second grammar. A GitHub tag
/// filter is a glob: it has no alternation and `[...]` matches one alphanumeric character, so two
/// things the grammar says cannot be written into `on.push.tags` at all. The first is that a number
/// carries no leading zero — `0|[1-9][0-9]*` is unwritable — and [numbersRefusalFor] is the one
/// place that closes it, because `01.2.3-stable-…` would be published here and then refused by
/// hostyour-manager/shared/release.ts:22 as no release at all. The second is that alpha is less ripe
/// than beta and beta less ripe than stable — [ReleaseChannel], after
/// hostyour-manager/shared/release.ts:12 — which is what decides whether a release is marked as a
/// pre-release. Neither answers "may this tag be pushed"; the filter answers that, on every run.
///
/// A TAG THE PARTS CANNOT BE READ OUT OF IS CARRIED THROUGH, NOT DROPPED. Whoever is deciding a
/// version has to see everything already standing on the remote, including the thing this file
/// cannot place.
library;

import 'release_tag_filter.dart';

/// The channels a release can be cut on, ordered by maturity — the ripest is the last.
///
/// THE AUTHORITY IS hostyour-manager/shared/release.ts:12, and this is the maturity order it states,
/// not a second copy of the tag grammar: which tags start a release is read from
/// [releaseWorkflowPath] on every run and nothing here overrides it. What this ranking decides is
/// what no glob can say — whether a release is a pre-release, and which environments a consumer
/// pinning the tag may then run it in.
///
/// THE CEILING IS NOT ENFORCED HERE. hostyour-manager/shared/release.ts:8 states that the channel is
/// a ceiling on which environment may run a tag and that the ceiling is enforced where deployments
/// are written, which is neither this program nor this repository.
enum ReleaseChannel {
  /// Reaches dev, and no further.
  alpha,

  /// Reaches dev and test, and no further.
  beta,

  /// Reaches everywhere.
  stable;

  /// The channel spelled [name], or null when no channel is spelled that way.
  static ReleaseChannel? named(String name) {
    for (final ReleaseChannel channel in values) {
      if (channel.name == name) {
        return channel;
      }
    }
    return null;
  }

  /// Every channel, spelled as a tag spells it, in the order they ripen.
  static List<String> get spelled =>
      values.map((ReleaseChannel each) => each.name).toList(growable: false);

  /// Whether a release on this channel is a pre-release, which is every channel but the ripest.
  ///
  /// ASKED OF THE RANKING AND NEVER OF THE TAG TEXT. Every tag under this grammar carries a hyphen
  /// and a channel, so "does it look pre-release" — the question a semantic-version tool asks of the
  /// text — answers yes for all three and would mark a finished release as unfinished.
  bool get isPreRelease => this != values.last;

  /// The channels this one has not ripened into yet, in the order they ripen.
  List<ReleaseChannel> get riper => values.sublist(index + 1);

  /// How far a tag on this channel may reach, as hostyour-manager/shared/release.ts:8 states it.
  String get reaches => switch (this) {
    ReleaseChannel.alpha => 'dev',
    ReleaseChannel.beta => 'dev and test',
    ReleaseChannel.stable => 'everywhere',
  };
}

/// The tag that [version] on [channel] composes when it is stamped at [at].
///
/// The stamp is taken at the moment the tag is composed and never typed: two releases of one version
/// on one channel are a real thing — the same code cut again from a later commit — and what tells
/// them apart is when each was minted.
String tagFor({required String version, required ReleaseChannel channel, required DateTime at}) =>
    '$version-${channel.name}-${stampOf(at)}';

/// [at] as the fourteen digits `yyyyMMddHHmmss` in UTC.
String stampOf(DateTime at) {
  final DateTime utc = at.toUtc();
  return '${_padded(utc.year, 4)}${_padded(utc.month, 2)}${_padded(utc.day, 2)}'
      '${_padded(utc.hour, 2)}${_padded(utc.minute, 2)}${_padded(utc.second, 2)}';
}

String _padded(int number, int digits) => number.toString().padLeft(digits, '0');

/// Why [version] must not be released though a filter would admit it, or null when it may be.
///
/// THE ONE THING THE GLOB CANNOT SAY. `[0-9]+` reads a number and no filter pattern can write
/// `0|[1-9][0-9]*`, so `01.2.3` passes `on.push.tags` and is no version:
/// hostyour-manager/shared/release.ts:22 refuses it, and a release published under a tag the
/// platform cannot parse is a release nothing downstream can read. Everything else about the shape
/// of a version — how many numbers, what stands between them — is left to the filter, so that no
/// version is refused twice for one reason. A version wrong in more than one way is answered here
/// first, because this refusal needs neither a file nor a clock, and by the filter on the next run.
String? numbersRefusalFor(String version) {
  for (final String number in version.split('.')) {
    if (number.length > 1 && number.startsWith('0') && _readsAsANumber(number)) {
      return '"$version" is no version: "$number" carries a leading zero, and '
          'hostyour-manager/shared/release.ts:22 reads each number as 0 or a digit from 1 to 9 '
          'followed by any digits. $releaseWorkflowPath cannot refuse this one — a filter pattern '
          'has no alternation — so it is refused here';
    }
  }
  return null;
}

/// Whether [segment] is the digits a number is written with and nothing else.
///
/// A segment carrying anything but digits is not a number with a leading zero — it is a version the
/// filter itself refuses, and the sentence above would name the wrong reason and then say the
/// workflow cannot refuse it, which it can. `0.1.0+7` splits into `0`, `1`, `0+7`.
bool _readsAsANumber(String segment) =>
    segment.runes.every((int rune) => rune >= 0x30 && rune <= 0x39);

/// A tag on origin the filter accepts, read into the parts a screen orders and marks it by.
final class ReleasedTag implements Comparable<ReleasedTag> {
  const ReleasedTag._({
    required this.tag,
    required this.major,
    required this.minor,
    required this.patch,
    required this.channelName,
    required this.stamp,
  });

  /// [tag] read into its parts, or null when they cannot be read out of it.
  ///
  /// The channel is read as whatever stands between the two hyphens and is NOT held to
  /// [ReleaseChannel] here: a filter widened to a channel this program does not rank must show up as
  /// a tag whose channel is unranked, and be refused by name where that matters, rather than be
  /// dropped off the screen as though it had never been released.
  static ReleasedTag? read(String tag) {
    final RegExpMatch? match = _parts.firstMatch(tag);
    if (match == null) {
      return null;
    }
    final List<int> numbers = <int>[
      for (final int group in <int>[1, 2, 3])
        if (match.group(group) case final String digits)
          if (int.tryParse(digits) case final int number) number,
    ];
    if (numbers.length != 3) {
      return null;
    }
    return ReleasedTag._(
      tag: tag,
      major: numbers[0],
      minor: numbers[1],
      patch: numbers[2],
      channelName: match.group(4)!,
      stamp: match.group(5)!,
    );
  }

  /// The tag as it stands on the remote.
  final String tag;

  /// The first number.
  final int major;

  /// The second number.
  final int minor;

  /// The third number.
  final int patch;

  /// The channel as the tag spells it, whether or not [ReleaseChannel] ranks it.
  final String channelName;

  /// The `yyyyMMddHHmmss` this tag was minted at, as the tag spells it.
  final String stamp;

  /// The channel this was released on, or null when nothing ranks the one it names.
  ReleaseChannel? get channel => ReleaseChannel.named(channelName);

  /// The three numbers on their own — `0.1.0` for `0.1.0-beta-20260821194500`.
  String get version => '$major.$minor.$patch';

  /// A fix to what this release does.
  String get nextPatch => '$major.$minor.${patch + 1}';

  /// Something this release did not do.
  String get nextMinor => '$major.${minor + 1}.0';

  /// A break with how this release was used.
  String get nextMajor => '${major + 1}.0.0';

  /// The numbers first, then when it was minted, then how ripe its channel is.
  ///
  /// The stamp is fourteen digits of fixed width, so comparing it as text IS comparing the moment it
  /// was minted at. Which of two releases of one version is the later one is a question of when each
  /// was cut and not of which channel it carries: a fix cut on alpha after a stable release is the
  /// later release, and a screen claiming otherwise would propose from the wrong one.
  @override
  int compareTo(ReleasedTag other) {
    for (final (int mine, int theirs) in <(int, int)>[
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
    ]) {
      final int decided = mine.compareTo(theirs);
      if (decided != 0) {
        return decided;
      }
    }
    final int minted = stamp.compareTo(other.stamp);
    if (minted != 0) {
      return minted;
    }
    return (channel?.index ?? -1).compareTo(other.channel?.index ?? -1);
  }

  static final RegExp _parts = RegExp(r'^([0-9]+)\.([0-9]+)\.([0-9]+)-([^-]+)-([0-9]+)$');
}

/// A version that could be typed next, and what makes it the obvious one.
///
/// The reason travels with the version because three numbers on their own say nothing about why they
/// are being offered, and the person reading them is deciding rather than picking.
final class Proposal {
  /// [version] is proposed [because].
  const Proposal({required this.version, required this.because});

  /// What could be typed.
  final String version;

  /// Why it is offered.
  final String because;
}

/// The tags standing on origin, sorted into what has been released and what could not be placed.
final class Releases {
  /// [releases] in ascending order, with [otherTags] holding what could not be placed as one.
  const Releases({required this.releases, required this.otherTags});

  /// What [tags] are, asked of [filter] and of nothing else.
  factory Releases.ofTags(Iterable<String> tags, {required TagFilter filter}) {
    final List<ReleasedTag> releases = <ReleasedTag>[];
    final List<String> otherTags = <String>[];
    for (final String tag in tags) {
      final ReleasedTag? released = filter.accepts(tag) ? ReleasedTag.read(tag) : null;
      if (released == null) {
        otherTags.add(tag);
      } else {
        releases.add(released);
      }
    }
    releases.sort();
    otherTags.sort();
    return Releases(releases: releases, otherTags: otherTags);
  }

  /// Every release, oldest first.
  final List<ReleasedTag> releases;

  /// The tags on origin that would have started no release, and the ones whose parts this file
  /// cannot read.
  final List<String> otherTags;

  /// The latest release, or null when nothing has been released.
  ReleasedTag? get latest => releases.isEmpty ? null : releases.last;

  /// Whether [tag] already stands on the remote, so that pushing it would be a second release of one
  /// name.
  bool holds(String tag) =>
      releases.any((ReleasedTag each) => each.tag == tag) || otherTags.contains(tag);

  /// The versions that could come next — offered, and none of them chosen.
  ///
  /// Nothing released yet is the first release, and the only version this repository states about
  /// itself is the one its packages declare, so [declaredVersion] is what is offered and nothing is
  /// invented when there is none. After a pre-release the obvious next thing is the same version on
  /// a riper channel, which under this grammar is a release of its own and not a rename of the last
  /// one. After a release on the ripest channel there are three directions and no way for a program
  /// to know which of them a change deserves — that is exactly the decision this program refuses to
  /// take — so all three are shown and the person types one of them or something else entirely.
  List<Proposal> proposals({required String? declaredVersion}) {
    final ReleasedTag? released = latest;
    if (released == null) {
      return <Proposal>[
        if (declaredVersion != null)
          Proposal(
            version: declaredVersion,
            because: 'the first release — the version every package of this repository declares',
          ),
      ];
    }
    final ReleaseChannel? channel = released.channel;
    if (channel == null) {
      return <Proposal>[
        Proposal(
          version: released.version,
          because:
              'the version ${released.tag} carries — nothing ranks its channel '
              '"${released.channelName}", so how ripe it is cannot be said here',
        ),
      ];
    }
    if (channel.isPreRelease) {
      return <Proposal>[
        Proposal(
          version: released.version,
          because:
              'the version ${released.tag} is at — released on ${channel.name}, and not yet on '
              '${released.channel!.riper.map((ReleaseChannel each) => each.name).join(' or ')}',
        ),
      ];
    }
    return <Proposal>[
      Proposal(
        version: released.nextPatch,
        because: 'the next patch — a fix to what ${released.tag} does',
      ),
      Proposal(
        version: released.nextMinor,
        because: 'the next minor — something ${released.tag} did not do',
      ),
      Proposal(
        version: released.nextMajor,
        because: 'the next major — a break with how ${released.tag} was used',
      ),
    ];
  }
}
