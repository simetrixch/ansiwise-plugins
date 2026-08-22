import 'dart:io';

import 'package:test/test.dart';

import '../../tool/paths.dart';
import '../../tool/release_packages.dart';
import '../../tool/release_tag_filter.dart';
import '../fakes.dart';

/// release-packages — one tag carries every package of this repository, and the tree at that tag
/// says so from the inside.
///
/// **The three claims this file holds.** The first is that the walk finds every package rather than
/// a list somebody maintained: it is run over THIS repository and held against the directories
/// really standing in it, so a package added without an edit anywhere is a package this check
/// notices. The second is that a release writes two things into every manifest — the one version,
/// and the tag stamped into every dependency one package here declares on another — because a tag
/// whose inside still names a branch pins nothing at all. The third is the other half of that
/// sentence: a dependency on ANOTHER repository is never stamped, and a release is refused while one
/// of them names a branch, because the tag being cut is a name in this repository and there is
/// nothing here to put a foreign ref right with.
///
/// **What the counter-probes are for.** A stamper that changed nothing would pass a check that only
/// looked at the result, so the tree BEFORE the bump is asserted to really carry the branch name the
/// stamp replaces. And a stamper matching the old value would work exactly once, so the bump is run
/// twice and the second one has a tag standing where `master` stood. For the third claim the probe
/// runs the other way as well: a tree whose foreign refs all name released tags is asserted to be
/// released, so a program that refused every tree would not read as one that refused the right one.
///
/// **How much the real-tree claim covers, and how much it does not.** What is asserted over this
/// repository is that every foreign dependency it carries is either a released tag or is reported —
/// none falls between the two. WHICH of the two it is today is deliberately not asserted: a check
/// pinning that would go red on the day the refs are pinned, which is the day it should stay green.
void main() {
  final Directory repository = repositoryOf(Directory.current);
  final TagFilter theFilter = TagFilter.ofWorkflow(
    File('${repository.path}/$releaseWorkflowPath').readAsStringSync(),
  );

  group('the packages this repository releases', () {
    final ReleasedPackages packages = ReleasedPackages.read(PubspecsInRepository(repository));

    test('are walked off the disk, not listed anywhere', () {
      final List<String> directories = <String>[
        for (final FileSystemEntity entry in repository.listSync())
          if (entry is Directory)
            if (entry.path.split(RegExp(r'[/\\]')).last case final String name)
              if (name.startsWith(packageDirectoryPrefix) &&
                  File('${entry.path}/pubspec.yaml').existsSync())
                name,
      ]..sort();

      expect(
        packages.manifests.map((ManifestState each) => each.directory),
        directories,
        reason:
            'the walk and the disk are the same set or a release publishes a tag with a package '
            'nobody bumped in it',
      );
      expect(
        directories,
        isNotEmpty,
        reason: 'nothing was walked, so every claim below is about an empty list',
      );
    });

    test('each declare a name and a version, and the release package declares no version', () {
      for (final ManifestState manifest in packages.manifests) {
        expect(manifest.declaredName, isNotNull, reason: '${manifest.path} declares no name');
        expect(manifest.declaredVersion, isNotNull, reason: '${manifest.path} declares no version');
      }
      expect(
        declaredVersionIn(File('pubspec.yaml').readAsStringSync()),
        isNull,
        reason:
            'this package ships no library and is nobody dependency, so a version here would state '
            'what somebody is holding when nobody is holding it',
      );
      expect(
        packages.manifests.map((ManifestState each) => each.directory),
        isNot(contains('release')),
        reason: 'the release package must not be released as one of the packages it releases',
      );
    });

    test('agree on one version, which is the one a first release is proposed from', () {
      expect(
        packages.refusal,
        isNull,
        reason:
            'one tag carries one version, so packages that disagree cannot be released under one '
            'name at all',
      );
      expect(packages.declaredVersion, isNotNull);
    });

    test('name this repository in one spelling, which the release page copies', () {
      expect(
        packages.siblingUrl,
        isNotNull,
        reason:
            'a package here depends on a sibling, and its url is the spelling the release page '
            'hands a consumer — pub reads two spellings of one address as two sources',
      );
    });
  });

  group('a repository whose packages disagree cannot be released', () {
    test('two versions are refused, and both are named with the packages carrying them', () {
      final ReleasedPackages packages = ReleasedPackages.read(
        ManifestsInMemory(<String, String>{
          'ansiwise-one/pubspec.yaml': plantedPubspec(name: 'ansiwise_one', version: '0.1.0'),
          'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.2.0'),
        }),
      );

      expect(packages.refusal, contains('0.1.0'));
      expect(packages.refusal, contains('0.2.0'));
      expect(packages.refusal, contains('ansiwise-one'));
      expect(packages.refusal, contains('ansiwise-two'));
      expect(
        packages.declaredVersion,
        isNull,
        reason: 'a version offered out of a disagreement would be one answer of two, silently',
      );
    });

    test('a package declaring no version is refused by name', () {
      final ReleasedPackages packages = ReleasedPackages.read(
        ManifestsInMemory(<String, String>{
          'ansiwise-one/pubspec.yaml': plantedPubspec(name: 'ansiwise_one', version: '0.1.0'),
          'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two'),
        }),
      );

      expect(packages.refusal, contains('ansiwise-two/pubspec.yaml'));
    });

    test('and packages that agree are refused for nothing', () {
      final ReleasedPackages packages = ReleasedPackages.read(
        ManifestsInMemory(<String, String>{
          'ansiwise-one/pubspec.yaml': plantedPubspec(name: 'ansiwise_one', version: '0.1.0'),
          'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.1.0'),
        }),
      );

      expect(
        packages.refusal,
        isNull,
        reason: 'a reader that refused everything would pass the two probes above',
      );
      expect(packages.declaredVersion, '0.1.0');
    });
  });

  group('reading a git dependency', () {
    test('takes the keys in whichever order they were written', () {
      for (final bool pathFirst in <bool>[false, true]) {
        final List<GitDependency> found = gitDependenciesIn(
          plantedPubspec(
            name: 'ansiwise_one',
            version: '0.1.0',
            dependsOn: <String, PlantedDependency>{
              'ansiwise_two': (path: 'ansiwise-two', ref: 'master'),
            },
            pathBeforeRef: pathFirst,
          ),
        );

        expect(found, hasLength(1));
        expect(found.single.path, 'ansiwise-two');
        expect(found.single.ref, 'master');
        expect(found.single.url, 'https://github.com/simetrixch/ansiwise-plugins.git');
        expect(
          found.single.package,
          'ansiwise_two',
          reason:
              'the name the block stands under is the word a person edits, and a refusal naming '
              'only the url would send them looking for which of two lines carried it',
        );
      }
    });

    test('names the dependency the block stands under, over this repository', () {
      final ManifestState manifest = ReleasedPackages.read(
        PubspecsInRepository(repository),
      ).manifests.first;

      expect(
        gitDependenciesIn(manifest.text).map((GitDependency each) => each.package),
        everyElement(isNotNull),
        reason:
            'these manifests write a comment above almost every dependency, and a walk that took '
            'the comment for the key would name a sentence where a package name belongs',
      );
      expect(
        gitDependenciesIn(manifest.text).map((GitDependency each) => each.package),
        contains('ansiwise_core'),
      );
    });

    test('and a comment standing between the name and the git block is stepped over', () {
      final GitDependency dependency = gitDependenciesIn(
        'name: ansiwise_one\n'
        'version: 0.1.0\n'
        '\n'
        'dependencies:\n'
        '  ansiwise_core:\n'
        '# the framework, see https://github.com/simetrixch/ansiwise-core\n'
        '    git:\n'
        '      url: https://github.com/simetrixch/ansiwise-core.git\n'
        '      ref: master\n',
      ).single;

      expect(
        dependency.package,
        'ansiwise_core',
        reason:
            'a comment may stand at any indent, and one carrying a colon read as the key would '
            'name a sentence in the line a person is sent to open',
      );
    });

    test('is a sibling when its path names a package of this repository, and not otherwise', () {
      final GitDependency dependency = gitDependenciesIn(
        plantedPubspec(
          name: 'ansiwise_one',
          version: '0.1.0',
          dependsOn: <String, PlantedDependency>{
            'ansiwise_two': (path: 'ansiwise-two', ref: 'master'),
          },
        ),
      ).single;

      expect(dependency.isSiblingOf(<String>{'ansiwise-one', 'ansiwise-two'}), isTrue);
      expect(
        dependency.isSiblingOf(<String>{'ansiwise-one'}),
        isFalse,
        reason:
            'what makes a dependency a sibling is that its path is a package HERE — a check that '
            'answered yes to any git dependency would stamp the framework and the audits too',
      );
    });

    test('over this repository, the siblings are the ones inside it and nothing else', () {
      final ReleasedPackages packages = ReleasedPackages.read(PubspecsInRepository(repository));
      final List<String> siblings = <String>[];
      final List<String> strangers = <String>[];
      for (final ManifestState manifest in packages.manifests) {
        for (final GitDependency each in gitDependenciesIn(manifest.text)) {
          (each.isSiblingOf(packages.directories) ? siblings : strangers).add(
            '${manifest.directory} → ${each.path ?? each.url}',
          );
        }
      }

      expect(
        siblings,
        isNotEmpty,
        reason:
            'this repository really does hold a package depending on its own siblings, and if it '
            'stopped doing so the stamping below would be checking a mechanism with nothing to do',
      );
      expect(
        strangers,
        isNotEmpty,
        reason:
            'every package here depends on the framework, which is another repository — a reader '
            'calling those siblings would stamp this tag into a dependency on somebody else',
      );
    });
  });

  group('what a release writes into the manifests', () {
    const String tag = '0.2.0-beta-20260901120000';

    ReleasedPackages plantedRepository() => ReleasedPackages.read(
      ManifestsInMemory(<String, String>{
        'ansiwise-one/pubspec.yaml': plantedPubspec(
          name: 'ansiwise_one',
          version: '0.1.0',
          dependsOn: <String, PlantedDependency>{
            'ansiwise_two': (path: 'ansiwise-two', ref: 'master'),
            'ansiwise_core': (path: null, ref: _theForeignTag),
          },
        ),
        'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.1.0'),
      }),
    );

    test('is the one version, in every manifest', () {
      final Bump bump = bumpFor(
        packages: plantedRepository(),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );

      expect(bump.isGreen, isTrue, reason: bump.refusal ?? '');
      expect(bump.texts, hasLength(2));
      for (final String text in bump.texts.values) {
        expect(declaredVersionIn(text), '0.2.0');
      }
    });

    test('and the tag, stamped into every dependency on a sibling and into no other', () {
      final ReleasedPackages before = plantedRepository();
      expect(
        before.manifests.first.text,
        contains('ref: master'),
        reason:
            'the tree being stamped has to really carry the branch name, or this check is green for '
            'a stamper that does nothing',
      );

      final Bump bump = bumpFor(packages: before, version: '0.2.0', tag: tag, filter: theFilter);
      final String stampedText = bump.texts['ansiwise-one/pubspec.yaml']!;
      final List<GitDependency> after = gitDependenciesIn(stampedText);

      expect(bump.stamped, <String>['ansiwise-one/pubspec.yaml → ansiwise-two']);
      expect(
        after.firstWhere((GitDependency each) => each.path == 'ansiwise-two').ref,
        tag,
        reason: 'a consumer naming this tag has to find the sibling at the same tag inside it',
      );
      expect(
        after.firstWhere((GitDependency each) => each.package == 'ansiwise_core').ref,
        _theForeignTag,
        reason:
            'the framework is another repository and this tag is a name in ours — writing it here '
            'would name a tag that repository does not have, so a consumer would resolve nothing '
            'at all',
      );
    });

    test('the second time as well, though a tag stands where the branch stood', () {
      final Bump first = bumpFor(
        packages: plantedRepository(),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );
      const String later = '0.3.0-stable-20261001120000';
      final Bump second = bumpFor(
        packages: ReleasedPackages.read(ManifestsInMemory(Map<String, String>.of(first.texts))),
        version: '0.3.0',
        tag: later,
        filter: theFilter,
      );

      expect(
        gitDependenciesIn(
          second.texts['ansiwise-one/pubspec.yaml']!,
        ).firstWhere((GitDependency each) => each.path == 'ansiwise-two').ref,
        later,
        reason:
            'a stamper that looked for "master" would work exactly once and leave every release '
            'after the first one naming the release before it',
      );
    });

    test('nothing at all when the manifests already say it', () {
      final Bump first = bumpFor(
        packages: plantedRepository(),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );
      final Bump again = bumpFor(
        packages: ReleasedPackages.read(ManifestsInMemory(Map<String, String>.of(first.texts))),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );

      expect(
        again.texts,
        isEmpty,
        reason:
            'a commit carrying no change is a commit saying nothing, and git refuses to make one — '
            'so the same version cut again on a riper channel has to be allowed to write nothing',
      );
      expect(again.already, hasLength(2));
    });

    test('and it refuses a sibling dependency carrying no ref line, rather than leaving it', () {
      final Bump bump = bumpFor(
        packages: ReleasedPackages.read(
          ManifestsInMemory(<String, String>{
            'ansiwise-one/pubspec.yaml':
                'name: ansiwise_one\n'
                'version: 0.1.0\n'
                '\n'
                'dependencies:\n'
                '  ansiwise_two:\n'
                '    git:\n'
                '      url: https://github.com/simetrixch/ansiwise-plugins.git\n'
                '      path: ansiwise-two\n',
            'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.1.0'),
          }),
        ),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );

      expect(bump.isGreen, isFalse);
      expect(bump.refusal, contains('ansiwise-two'));
      expect(
        bump.refusal,
        contains('ref'),
        reason:
            'a git dependency with no ref resolves the default branch, which is the pin this '
            'release exists to replace — publishing it silently is the one outcome to avoid',
      );
    });
  });

  group('a dependency on another repository is not stamped, so it has to be pinned already', () {
    const String tag = '0.2.0-beta-20260901120000';

    ReleasedPackages plantedRepository({required String coreRef, required String checksRef}) =>
        ReleasedPackages.read(
          ManifestsInMemory(<String, String>{
            'ansiwise-one/pubspec.yaml': plantedPubspec(
              name: 'ansiwise_one',
              version: '0.1.0',
              dependsOn: <String, PlantedDependency>{
                'ansiwise_two': (path: 'ansiwise-two', ref: 'master'),
                'ansiwise_core': (path: null, ref: coreRef),
              },
            ),
            'ansiwise-two/pubspec.yaml': plantedPubspec(
              name: 'ansiwise_two',
              version: '0.1.0',
              dependsOn: <String, PlantedDependency>{
                'ansiwise_checks': (path: 'registry', ref: checksRef),
              },
            ),
          }),
        );

    test('a branch stops the release, and the line, the package and the ref are all named', () {
      final ReleasedPackages packages = plantedRepository(
        coreRef: 'master',
        checksRef: _theForeignTag,
      );
      final Bump bump = bumpFor(packages: packages, version: '0.2.0', tag: tag, filter: theFilter);

      expect(bump.isGreen, isFalse);
      expect(bump.texts, isEmpty, reason: 'a refused release leaves a tree nobody has to put back');
      expect(bump.refusal, contains('ansiwise-one/pubspec.yaml:'));
      expect(bump.refusal, contains('ansiwise_core'));
      expect(bump.refusal, contains('"master"'));
      expect(
        bump.refusal,
        isNot(contains('ansiwise_checks')),
        reason:
            'the one already naming a released tag is not a line anybody has to touch, and a '
            'refusal listing it would send somebody to a file that is right',
      );
    });

    test('and a block with no ref line at all is stopped by the same question', () {
      final Bump bump = bumpFor(
        packages: ReleasedPackages.read(
          ManifestsInMemory(<String, String>{
            'ansiwise-one/pubspec.yaml':
                'name: ansiwise_one\n'
                'version: 0.1.0\n'
                '\n'
                'dependencies:\n'
                '  ansiwise_core:\n'
                '    git:\n'
                '      url: https://github.com/simetrixch/ansiwise-core.git\n',
          }),
        ),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );

      expect(bump.isGreen, isFalse);
      expect(
        bump.refusal,
        contains('no ref at all, which is the default branch'),
        reason:
            'pub resolves the default branch when no ref is written, so a block carrying none is '
            'the same pin as one naming master and has to read as one',
      );
    });

    test('every one of them is named at once, rather than one refusal per run', () {
      final Bump bump = bumpFor(
        packages: plantedRepository(coreRef: 'master', checksRef: 'master'),
        version: '0.2.0',
        tag: tag,
        filter: theFilter,
      );

      expect(bump.refusal, contains('ansiwise-one/pubspec.yaml:'));
      expect(
        bump.refusal,
        contains('ansiwise-two/pubspec.yaml:'),
        reason:
            'twelve manifests naming the framework are twelve lines to put right, and one refusal '
            'per run is twelve runs to find them',
      );
    });

    test('and a tree whose foreign refs are all released tags is refused for nothing', () {
      final ReleasedPackages packages = plantedRepository(
        coreRef: _theForeignTag,
        checksRef: _theForeignTag,
      );
      final Bump bump = bumpFor(packages: packages, version: '0.2.0', tag: tag, filter: theFilter);

      expect(
        packages.followed(theFilter),
        isEmpty,
        reason: 'a program that refused every tree would pass all three probes above',
      );
      expect(bump.isGreen, isTrue, reason: bump.refusal ?? '');
      expect(
        gitDependenciesIn(
          bump.texts['ansiwise-one/pubspec.yaml']!,
        ).firstWhere((GitDependency each) => each.package == 'ansiwise_core').ref,
        _theForeignTag,
        reason: 'what was already right is left exactly as it stood',
      );
    });

    test('and what is reported opens with the line a person has to open', () {
      final ReleasedPackages packages = plantedRepository(
        coreRef: 'master',
        checksRef: _theForeignTag,
      );

      expect(packages.followed(theFilter), <String>[
        'ansiwise-one/pubspec.yaml:12 ansiwise_core at "master"',
      ]);
    });

    test('over this repository, every foreign ref is judged and none falls between', () {
      final ReleasedPackages packages = ReleasedPackages.read(PubspecsInRepository(repository));
      final List<String> foreign = <String>[];
      final List<String> pinned = <String>[];
      int siblings = 0;
      // A `git:` KEY, in whichever of the two shapes YAML allows it to be written: on a line of
      // its own with the block indented under it, or inline inside braces. This is the second
      // reader the assertion at the end of this test needs, and it must share no code with
      // gitDependenciesIn or it would go blind in the same places.
      //
      // BOTH SHAPES ARE COUNTED BECAUSE ONLY ONE OF THEM IS PARSED. A first draft of this matched
      // `git:` alone on a line, and an inline `dep: {git: {url: ..., ref: master}}` planted in a
      // manifest stayed GREEN — the parser did not see it and neither did the counter, so the two
      // agreed about a dependency nobody had looked at. That is the exact failure this assertion
      // exists to report, reproduced by the assertion itself.
      //
      // The lookahead keeps a `git://` URL out: `url: git://host/x` would otherwise read as a key
      // because of the space in front of it.
      final RegExp aGitKey = RegExp(r'(?:^|[{,\s])git[ \t]*:(?!//)', multiLine: true);
      int gitKeys = 0;
      for (final ManifestState manifest in packages.manifests) {
        gitKeys += aGitKey.allMatches(manifest.text).length;
        for (final GitDependency each in gitDependenciesIn(manifest.text)) {
          if (each.isSiblingOf(packages.directories)) {
            siblings += 1;
            continue;
          }
          foreign.add(followedAs(manifest.path, each));
          if (each.isReleased(theFilter)) {
            pinned.add(followedAs(manifest.path, each));
          }
        }
      }

      expect(
        foreign,
        isNotEmpty,
        reason:
            'every package here depends on the framework, and an empty list would make the claim '
            'below one about nothing',
      );
      expect(
        <String>[...pinned, ...packages.followed(theFilter)]..sort(),
        foreign..sort(),
        reason:
            'each foreign dependency is either a released tag or is reported as followed — one '
            'falling between the two would be a ref nothing looked at, which is what this whole '
            'check exists to stop',
      );

      // THE ASSERTION ABOVE CANNOT GO RED ON ITS OWN, and saying so is cheaper than letting a
      // reader trust it further than it goes. Both of its sides are built out of the subject's own
      // gitDependenciesIn, isSiblingOf, isReleased and followedAs, so it compares one formula
      // against itself: a dependency the parser cannot SEE is missing from the left side and from
      // the right side alike, and the two still match while nothing looked at that ref.
      //
      // So the count is taken a second time by a reader that shares nothing with the first: every
      // `git:` key the manifests write, matched as a line. It is coarse on purpose — it knows
      // nothing of siblings, refs or releases — and that is exactly why a block the parser lost
      // track of shows up here as a number that does not add up.
      expect(
        foreign.length + siblings,
        gitKeys,
        reason:
            'the manifests of this repository write $gitKeys git: key(s), and the parser answered '
            '${foreign.length} foreign plus $siblings sibling. A key that is in neither is a '
            'dependency the parser did not see, and the comparison above cannot report it because '
            'it is absent from both of its sides',
      );
    });
  });
}

/// A tag of ANOTHER repository, as a manifest here would write it once that repository has released.
///
/// It is spelled out rather than composed, and it is deliberately not a tag of this repository: what
/// the checks below hold is that such a ref is left where it stands, so a value that happened to
/// equal the tag being cut would agree with a stamper that overwrote it.
const String _theForeignTag = '0.4.1-stable-20260701090000';
