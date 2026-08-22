import 'dart:io';

import 'package:test/test.dart';

import '../../tool/paths.dart';
import '../../tool/release_packages.dart';
import '../fakes.dart';

/// release-packages — one tag carries every package of this repository, and the tree at that tag
/// says so from the inside.
///
/// **The two claims this file holds.** The first is that the walk finds every package rather than a
/// list somebody maintained: it is run over THIS repository and held against the directories really
/// standing in it, so a package added without an edit anywhere is a package this check notices. The
/// second is that a release writes two things into every manifest — the one version, and the tag
/// stamped into every dependency one package here declares on another — because a tag whose inside
/// still names a branch pins nothing at all.
///
/// **What the counter-probes are for.** A stamper that changed nothing would pass a check that only
/// looked at the result, so the tree BEFORE the bump is asserted to really carry the branch name the
/// stamp replaces. And a stamper matching the old value would work exactly once, so the bump is run
/// twice and the second one has a tag standing where `master` stood.
void main() {
  final Directory repository = repositoryOf(Directory.current);

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
            dependsOn: <String, String>{'ansiwise_two': 'ansiwise-two'},
            pathBeforeRef: pathFirst,
          ),
        );

        expect(found, hasLength(1));
        expect(found.single.path, 'ansiwise-two');
        expect(found.single.ref, 'master');
        expect(found.single.url, 'https://github.com/simetrixch/ansiwise-plugins.git');
      }
    });

    test('is a sibling when its path names a package of this repository, and not otherwise', () {
      final GitDependency dependency = gitDependenciesIn(
        plantedPubspec(
          name: 'ansiwise_one',
          version: '0.1.0',
          dependsOn: <String, String>{'ansiwise_two': 'ansiwise-two'},
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
          dependsOn: <String, String>{'ansiwise_two': 'ansiwise-two', 'ansiwise_core': 'core'},
        ),
        'ansiwise-two/pubspec.yaml': plantedPubspec(name: 'ansiwise_two', version: '0.1.0'),
      }),
    );

    test('is the one version, in every manifest', () {
      final Bump bump = bumpFor(packages: plantedRepository(), version: '0.2.0', tag: tag);

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

      final Bump bump = bumpFor(packages: before, version: '0.2.0', tag: tag);
      final String stampedText = bump.texts['ansiwise-one/pubspec.yaml']!;
      final List<GitDependency> after = gitDependenciesIn(stampedText);

      expect(bump.stamped, <String>['ansiwise-one/pubspec.yaml → ansiwise-two']);
      expect(
        after.firstWhere((GitDependency each) => each.path == 'ansiwise-two').ref,
        tag,
        reason: 'a consumer naming this tag has to find the sibling at the same tag inside it',
      );
      expect(
        after.firstWhere((GitDependency each) => each.path == 'core').ref,
        'master',
        reason:
            'the framework is another repository and this tag says nothing about it — stamping it '
            'here would pin somebody else to a name of ours',
      );
    });

    test('the second time as well, though a tag stands where the branch stood', () {
      final Bump first = bumpFor(packages: plantedRepository(), version: '0.2.0', tag: tag);
      const String later = '0.3.0-stable-20261001120000';
      final Bump second = bumpFor(
        packages: ReleasedPackages.read(ManifestsInMemory(Map<String, String>.of(first.texts))),
        version: '0.3.0',
        tag: later,
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
      final Bump first = bumpFor(packages: plantedRepository(), version: '0.2.0', tag: tag);
      final Bump again = bumpFor(
        packages: ReleasedPackages.read(ManifestsInMemory(Map<String, String>.of(first.texts))),
        version: '0.2.0',
        tag: tag,
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
}
