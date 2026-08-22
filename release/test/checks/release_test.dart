import 'dart:io';

import 'package:test/test.dart';

import '../../tool/paths.dart';
import '../../tool/release_command.dart';
import '../../tool/release_git.dart';
import '../../tool/release_report.dart';
import '../../tool/release_tag_filter.dart';
import '../../tool/release_versions.dart';
import '../fakes.dart';

/// release — a version and a channel compose the one tag that starts a release, the tag is held
/// against the filter that really decides, and nothing reaches a remote unless a person typed both.
///
/// **What cannot be shown by running it.** A real accepted run pushes a commit and a tag to GitHub,
/// which no check may do. So the deciding half is driven over a scripted git and manifests that are
/// values: what it was asked to run is a list of argument lists in order, and both claims of this
/// program are readable in it — the screen RUNS ONLY READS, and a version and a channel that are
/// typed reach `git push` as the last of exactly eight commands. NO INVOCATION HERE IS AN ACCEPTING
/// ONE at the process level, on purpose.
///
/// **Where the grammar comes from is itself checked.** The program carries no admission grammar; it
/// reads `on.push.tags` out of .github/workflows/release.yml. The counter-probe for that is a
/// planted workflow whose filter says something else — the same tag is then accepted or refused
/// according to the file, which a program with its own copy of the grammar could not do. The two
/// things the program DOES state — that a number carries no leading zero, and that alpha is less
/// ripe than stable — are the two a glob cannot say, and each has a counter-probe of its own.
void main() {
  final Directory repository = repositoryOf(Directory.current);
  final String workflow = File('${repository.path}/$releaseWorkflowPath').readAsStringSync();
  final TagFilter theFilter = TagFilter.ofWorkflow(workflow);

  group('which tags start a release', () {
    test('is read from the workflow this repository really has', () {
      expect(
        theFilter.unreadable,
        isNull,
        reason: 'the file that decides whether a tag starts anything has to be readable here',
      );
      expect(theFilter.stated, hasLength(ReleaseChannel.values.length));
    });

    test('is three numbers, a channel, and fourteen digits — and nothing else', () {
      for (final String tag in <String>[
        '0.1.0-alpha-20260821194500',
        '0.1.0-beta-20260821194500',
        '0.1.0-stable-20260901120000',
        '1.4.2-beta-20260901120000',
        '10.0.0-stable-20991231235959',
      ]) {
        expect(
          theFilter.accepts(tag),
          isTrue,
          reason:
              '"$tag" is a tag by the grammar hostyour-manager/shared/release.ts:22 owns, and a '
              'filter that refused one would leave a person unable to release it',
        );
      }

      for (final String notATag in <String>[
        '0.1.0',
        '0.1.0-alpha',
        '0.1.0-beta.2',
        '0.1.0-stable-',
        '0.1.0-stable-2026082119450',
        '0.1.0-stable-202608211945000',
        '0.1.0-gamma-20260821194500',
        'v0.1.0-stable-20260821194500',
        '0.1.0+7',
        'master',
      ]) {
        expect(
          theFilter.accepts(notATag),
          isFalse,
          reason:
              '"$notATag" is no tag under this grammar, and a tag that starts a release is what '
              'every consumer then names as its ref',
        );
      }
    });

    test('and the one thing no filter pattern can say is said by the program instead', () {
      expect(
        theFilter.accepts('01.2.3-stable-20260821194500'),
        isTrue,
        reason: 'this is the gap the workflow states, and a check that hid it would state none',
      );
      expect(numbersRefusalFor('01.2.3'), contains('leading zero'));
      expect(
        numbersRefusalFor('1.2.3'),
        isNull,
        reason: 'a rule that refused every version would pass the probe above and release nothing',
      );
      expect(
        numbersRefusalFor('0.1.0'),
        isNull,
        reason: 'a bare 0 is a number; only a zero in FRONT of a digit is the refused shape',
      );
    });

    test('is read, and not restated — a workflow saying something else answers differently', () {
      const String tag = '0.1.0-alpha-20260821194500';
      final TagFilter planted = TagFilter.ofWorkflow(
        'name: planted\n'
        'on:\n'
        '  push:\n'
        '    tags:\n'
        "      - 'nothing-like-a-version'\n",
      );

      expect(theFilter.accepts(tag), isTrue);
      expect(
        planted.accepts(tag),
        isFalse,
        reason:
            'the same tag, two files, two answers — a program carrying its own copy of the grammar '
            'could not do this, and would go on accepting what the workflow had stopped triggering '
            'on',
      );
      expect(planted.refusalFor(tag), contains(releaseWorkflowPath));
    });

    test('and a workflow this program cannot read refuses rather than accepting everything', () {
      final TagFilter unreadable = TagFilter.ofWorkflow(
        'on:\n'
        '  push:\n'
        '    tags:\n'
        "      - '!0.1.0-alpha-20260821194500'\n",
      );

      expect(unreadable.unreadable, contains('!'));
      expect(unreadable.accepts('0.1.0-alpha-20260821194500'), isFalse);
    });
  });

  group('the channel is ranked, and the ranking is what marks a pre-release', () {
    test('alpha and beta are pre-releases and stable is not', () {
      expect(ReleaseChannel.alpha.isPreRelease, isTrue);
      expect(ReleaseChannel.beta.isPreRelease, isTrue);
      expect(ReleaseChannel.stable.isPreRelease, isFalse);
    });

    test('and the hyphen every tag carries is why the marking is not read off the text', () {
      for (final ReleaseChannel channel in ReleaseChannel.values) {
        final String tag = tagFor(version: '1.0.0', channel: channel, at: DateTime.utc(2026, 9));
        expect(
          tag,
          contains('-'),
          reason:
              'every tag under this grammar carries a hyphen, so "does it look like a pre-release" '
              'answers yes for all three and would mark a finished release as unfinished',
        );
      }
    });

    test('a channel nothing ranks is refused by name rather than guessed at', () {
      expect(ReleaseChannel.named('gamma'), isNull);
      expect(ReleaseChannel.named('stable'), ReleaseChannel.stable);
    });
  });

  group('the tag a version and a channel compose', () {
    test('is the grammar, stamped from the clock and never typed', () {
      expect(
        tagFor(
          version: '0.1.0',
          channel: ReleaseChannel.alpha,
          at: DateTime.utc(2026, 8, 21, 19, 45),
        ),
        '0.1.0-alpha-20260821194500',
      );
      expect(stampOf(DateTime.utc(2026, 1, 2, 3, 4, 5)), '20260102030405');
    });

    test('and is one the workflow of this repository really triggers on', () {
      for (final ReleaseChannel channel in ReleaseChannel.values) {
        expect(
          theFilter.accepts(tagFor(version: '0.1.0', channel: channel, at: DateTime.utc(2026, 9))),
          isTrue,
          reason:
              'a version a person may type has to be releasable on every channel this program '
              'offers — a proposal the workflow would ignore is a proposal that starts nothing',
        );
      }
    });
  });

  group('showing what has been released', () {
    test('runs only reads, and pushes nothing', () async {
      final ScriptedGit git = ScriptedGit();
      final ReleaseOutcome outcome = await _command(git, theFilter).show();

      expect(outcome.isGreen, isTrue);
      expect(git.spelled, <String>[
        'ls-remote --tags origin',
        'rev-parse --abbrev-ref HEAD',
        'rev-parse --short HEAD',
      ]);
      for (final String forbidden in <String>['push', 'commit', 'tag', 'add']) {
        expect(
          git.spelled.where((String each) => each.startsWith(forbidden)),
          isEmpty,
          reason: 'the screen changes nothing, and "$forbidden" changes something',
        );
      }
    });

    test('names every package the tag would carry, and what each declares', () async {
      final ReleaseOutcome outcome = await _command(ScriptedGit(), theFilter).show();

      expect(outcome.text, contains('ansiwise-one'));
      expect(outcome.text, contains('ansiwise_two'));
      expect(outcome.text, contains('0.1.0'));
      expect(
        outcome.text,
        contains('nothing — every dependency on another repository names a released tag'),
        reason:
            'a screen that said nothing when there is nothing to say would leave a person unable '
            'to tell it from one that never looked',
      );
    });

    test('and names what is followed rather than pinned, beside what could come next', () async {
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: ScriptedGit(),
        manifests: _manifests(foreignRef: 'master'),
        filter: theFilter,
        now: () => _theMoment,
      ).show();

      expect(outcome.text, contains('ansiwise_core at "master"'));
      expect(
        outcome.text,
        contains('possible next versions'),
        reason:
            'the versions offered are the ones this program would refuse while that line stands, '
            'so the two have to be read on one screen',
      );
    });

    test('and a remote that could not be read is not an empty remote', () async {
      final ScriptedGit git = ScriptedGit(
        answers: <String, GitAnswer>{
          'ls-remote --tags origin': const GitAnswer(status: 128, output: 'no such remote'),
        },
      );
      final ReleaseOutcome outcome = await _command(git, theFilter).show();

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('no such remote'));
      expect(
        outcome.text,
        contains('must not be read as an empty remote'),
        reason:
            'a failed read and a repository with no tags answer with the same empty list, and one '
            'of them means nothing at all',
      );
    });
  });

  group('a version and a channel that are typed', () {
    test('reach git push as the last of exactly eight commands', () async {
      final ScriptedGit git = _gitWithoutTheTag();
      final ManifestsInMemory manifests = _manifests();
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: git,
        manifests: manifests,
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(outcome.isGreen, isTrue, reason: outcome.text);
      expect(git.spelled, <String>[
        'status --porcelain',
        'rev-parse -q --verify refs/tags/$_theTag',
        'ls-remote --tags origin',
        'add -- ansiwise-one/pubspec.yaml ansiwise-two/pubspec.yaml',
        'commit -m release: $_theTag',
        'tag -a $_theTag -m $_theTag',
        'push origin HEAD',
        'push origin refs/tags/$_theTag',
      ]);
      expect(
        git.spelled.where((String each) => each.startsWith('push origin refs/tags/')),
        hasLength(1),
        reason: 'one release is one tag, and a second push of one would be a second release of it',
      );
      expect(manifests.written, hasLength(2));
      expect(outcome.text, contains(_theTag));
      expect(
        outcome.text,
        contains('THE RELEASE CARRIES NO FILE'),
        reason: 'a person has to be told that no artefact is coming, or they will wait for one',
      );
    });

    test('and the manifests they wrote carry the version and the tag', () async {
      final ManifestsInMemory manifests = _manifests();
      await ReleaseCommand(
        git: _gitWithoutTheTag(),
        manifests: manifests,
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(manifests.texts['ansiwise-one/pubspec.yaml'], contains('version: 0.2.0'));
      expect(manifests.texts['ansiwise-two/pubspec.yaml'], contains('version: 0.2.0'));
      expect(
        manifests.texts['ansiwise-one/pubspec.yaml'],
        contains('ref: $_theTag'),
        reason:
            'the commit the tag names has to say the tag from the inside, or a consumer pinning it '
            'resolves the sibling from a branch',
      );
      expect(
        manifests.texts['ansiwise-one/pubspec.yaml'],
        isNot(contains('ref: master')),
        reason: 'this is the pin the whole release exists to replace',
      );
    });
  });

  group('and what stops one before anything is pushed', () {
    test('a channel nothing ranks, named as the half that stopped it', () async {
      final ScriptedGit git = ScriptedGit();
      final ReleaseOutcome outcome = await _command(git, theFilter).release('0.2.0', 'gamma');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('gamma'));
      expect(outcome.text, contains('alpha, beta, stable'));
      expect(git.asked, isEmpty, reason: 'this refusal needs no network at all');
    });

    test('a version with a leading zero, which the filter itself would admit', () async {
      final ScriptedGit git = ScriptedGit();
      final ReleaseOutcome outcome = await _command(git, theFilter).release('01.2.3', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('leading zero'));
      expect(git.asked, isEmpty);
    });

    test('a version the workflow does not trigger on, told apart from the channel', () async {
      final ReleaseOutcome outcome = await _command(
        ScriptedGit(),
        theFilter,
      ).release('0.2', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(
        outcome.text,
        contains('the channel "beta" is one it does, so the version is what stopped it'),
        reason: 'two arguments were typed and the person has to be told which of them was wrong',
      );
    });

    test('a working tree that is not clean', () async {
      final ScriptedGit git = ScriptedGit(
        answers: <String, GitAnswer>{
          'status --porcelain': const GitAnswer(status: 0, output: ' M ansiwise-http/lib/x.dart\n'),
        },
      );
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: git,
        manifests: _manifests(),
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('ansiwise-http/lib/x.dart'));
      expect(git.spelled.where((String each) => each.startsWith('push')), isEmpty);
    });

    test('a tag that already stands on the remote', () async {
      final ScriptedGit git = ScriptedGit(
        answers: <String, GitAnswer>{
          'rev-parse -q --verify refs/tags/$_theTag': const GitAnswer(status: 1, output: ''),
          'ls-remote --tags origin': const GitAnswer(
            status: 0,
            output: 'aaaa\trefs/tags/$_theTag\n',
          ),
        },
      );
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: git,
        manifests: _manifests(),
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('already stands on origin'));
      expect(git.spelled.where((String each) => each.startsWith('push')), isEmpty);
    });

    test('a dependency on another repository still naming a branch', () async {
      final ScriptedGit git = _gitWithoutTheTag();
      final ManifestsInMemory manifests = _manifests(foreignRef: 'master');
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: git,
        manifests: manifests,
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('ansiwise_core'));
      expect(outcome.text, contains('"master"'));
      expect(
        manifests.written,
        isEmpty,
        reason: 'a refused release writes no manifest, so there is nothing for anybody to put back',
      );
      expect(
        git.spelled.where((String each) => each.startsWith('push')),
        isEmpty,
        reason:
            'the tag would carry twelve manifests resolving the framework from whatever master '
            'holds that day, and once pushed a tag is what a consumer pins',
      );
      expect(
        git.spelled.where((String each) => each.startsWith('commit')),
        isEmpty,
        reason: 'nothing is committed either, or the next run would tag a commit nobody asked for',
      );
    });

    test('packages that do not agree on one version', () async {
      final ScriptedGit git = ScriptedGit();
      final ReleaseOutcome outcome = await ReleaseCommand(
        git: git,
        manifests: ManifestsInMemory(<String, String>{
          'ansiwise-one/pubspec.yaml': plantedPubspec(name: 'ansiwise_one', version: '0.1.0'),
          'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.9.9'),
        }),
        filter: theFilter,
        now: () => _theMoment,
      ).release('0.2.0', 'beta');

      expect(outcome.isGreen, isFalse);
      expect(outcome.text, contains('different versions'));
      expect(
        git.asked,
        isEmpty,
        reason:
            'a repository that cannot be released under one name has no reason to ask a remote '
            'about it first',
      );
    });
  });

  group('help', () {
    test('says what a release of a library is, and does not restate the grammar', () {
      expect(helpText, contains('libraries'));
      expect(helpText, contains('ONE TAG CARRIES EVERY PACKAGE HERE'));
      expect(
        helpText,
        isNot(contains('[0-9]')),
        reason:
            'the one place that decides which tags are admitted is the workflow, and a help text '
            'carrying a copy of it would be the second spelling this repository avoids',
      );
    });
  });
}

/// The moment every tag composed here is stamped from, so the tag a typed version becomes is known
/// to the assertions as well as to the program.
final DateTime _theMoment = DateTime.utc(2026, 9, 1, 12);

/// What `0.2.0` on `beta` composes at [_theMoment], spelled out rather than composed a second time:
/// a check that built the expected tag with the same function the program uses would agree with it
/// however either of them was wrong.
const String _theTag = '0.2.0-beta-20260901120000';

ReleaseCommand _command(ScriptedGit git, TagFilter filter) =>
    ReleaseCommand(git: git, manifests: _manifests(), filter: filter, now: () => _theMoment);

ManifestsInMemory _manifests({String foreignRef = _theForeignTag}) =>
    ManifestsInMemory(<String, String>{
      'ansiwise-one/pubspec.yaml': plantedPubspec(
        name: 'ansiwise_one',
        version: '0.1.0',
        dependsOn: <String, PlantedDependency>{
          'ansiwise_two': (path: 'ansiwise-two', ref: 'master'),
          'ansiwise_core': (path: null, ref: foreignRef),
        },
      ),
      'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.1.0'),
    });

/// A tag of ANOTHER repository, as a manifest here writes it once that repository has released.
///
/// The planted tree carries a dependency on the framework because every real manifest here does, and
/// a tree without one would let a release pass a question this program now asks of every manifest.
const String _theForeignTag = '0.4.1-stable-20260701090000';

ScriptedGit _gitWithoutTheTag() => ScriptedGit(
  answers: <String, GitAnswer>{
    'rev-parse -q --verify refs/tags/$_theTag': const GitAnswer(status: 1, output: ''),
  },
);
