import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/paths.dart';
import '../../tool/gate/resolved_packages.dart';

/// resolved-packages — the checks and the code they judge are one copy, not two.
///
/// This plugin names the four tool packages by a git ref, and both the override file and the lock
/// file are gitignored. Without the untracked override the composition is resolved out of a COMMIT
/// while each tool package's own checks walk the working tree beside it — so one half of the gate
/// judges the bytes on disk and the other half judges bytes from somewhere else, and the verdict is
/// green across the split. Only a path-level disagreement is loud; a step whose body changed and
/// whose name did not produces no output at all.
///
/// So the gate REFUSES rather than describing it. Naming the revision of each package would be
/// accurate and would let the split stand: the working tree has no revision — it is a commit plus
/// whatever is uncommitted, which is the whole reason somebody is running the gate — so a verdict
/// saying "this commit here, the working tree there" would state the problem and pass anyway.
///
/// What decides is `.dart_tool/package_config.json`, which `dart pub get` writes and which names the
/// directory that actually answered, whatever asked for it.
void main() {
  final List<DartPackage> packages = dartPackagesIn(repositoryOf(Directory.current));

  test('this repository holds packages to check the resolution of', () {
    expect(
      packages,
      isNotEmpty,
      reason: 'with no package found, everything below is green about nothing',
    );
  });

  test('every package of this repository was composed from this repository', () {
    final List<ResolvedDependency> resolutions = <ResolvedDependency>[
      for (final DartPackage package in packages) ...inRepositoryResolutionOf(package, packages),
    ];
    expect(
      resolutions,
      isNotEmpty,
      reason:
          'no package of this repository depends on another one of it, so this check measured '
          'nothing — or nothing has been resolved yet',
    );
    expect(
      splitResolutions(resolutions: resolutions, repositoryPackages: packages),
      isEmpty,
      reason:
          'the fix is a pubspec_overrides.yaml pointing at the sibling checkout, so the audits and '
          'the code they audit are the same bytes',
    );
  });

  group('counter-probe', () {
    const DartPackage product = DartPackage(directory: '/work/product', name: 'product');
    const DartPackage tool = DartPackage(directory: '/work/tool-plugin', name: 'tool_plugin');
    const List<DartPackage> repository = <DartPackage>[product, tool];

    test('a package composed from somewhere else is reported, naming both copies', () {
      final List<String> refusals = splitResolutions(
        resolutions: const <ResolvedDependency>[
          ResolvedDependency(
            inPackage: 'product',
            name: 'tool_plugin',
            root: '/cache/git/ansiwise-plugins-abc123/tool-plugin',
          ),
        ],
        repositoryPackages: repository,
      );
      expect(
        refusals,
        hasLength(1),
        reason: 'this refusal cannot go red on the split it exists for',
      );
      expect(
        refusals.single,
        allOf(contains('/cache/git/ansiwise-plugins-abc123/tool-plugin'), contains(tool.directory)),
        reason: 'a refusal naming one of the two copies leaves the reader to guess at the other',
      );
    });

    test('a package composed from its checkout in this repository is not reported', () {
      expect(
        splitResolutions(
          resolutions: const <ResolvedDependency>[
            ResolvedDependency(
              inPackage: 'product',
              name: 'tool_plugin',
              root: '/work/tool-plugin',
            ),
          ],
          repositoryPackages: repository,
        ),
        isEmpty,
        reason: 'a refusal that reported everything would pass the probe above',
      );
    });

    test('a dependency this repository does not hold is nobody here to judge', () {
      expect(
        splitResolutions(
          resolutions: const <ResolvedDependency>[
            ResolvedDependency(
              inPackage: 'product',
              name: 'third_party',
              root: '/cache/hosted/third_party-1.0.0',
            ),
          ],
          repositoryPackages: repository,
        ),
        isEmpty,
        reason: 'it resolves through the pub cache by design, and nothing here judges it',
      );
    });

    test('the same directory written two ways is the same directory', () {
      expect(sameDirectory(r'D:\work\tool-plugin', 'D:/work/tool-plugin/'), isTrue);
      expect(
        sameDirectory('/work/tool-plugin', '/work/Tool-Plugin'),
        isFalse,
        reason:
            'a path that differs only in case is a different path on the machine the product runs '
            'on, and the gate is not the place to start treating the two as one',
      );
    });

    test('a resolution is read out of the package config a resolution really writes', () {
      // The reading itself, over a planted config in the shape pub writes: a relative rootUri
      // beside the file, and one entry naming a package this repository does not hold.
      final Directory scratch = Directory.systemTemp.createTempSync('hostyour-cloud-resolved-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      final Directory sibling = Directory('${scratch.path}/tool-plugin')..createSync();
      final DartPackage planted = DartPackage(
        directory: '${scratch.path}/product',
        name: 'product',
      );
      Directory('${planted.directory}/.dart_tool').createSync(recursive: true);
      File('${planted.directory}/.dart_tool/package_config.json').writeAsStringSync(
        '{"configVersion":2,"packages":['
        '{"name":"product","rootUri":"../","packageUri":"lib/"},'
        '{"name":"tool_plugin","rootUri":"../../tool-plugin","packageUri":"lib/"},'
        '{"name":"third_party","rootUri":"/cache/third_party","packageUri":"lib/"}'
        ']}',
      );

      final List<ResolvedDependency> read = inRepositoryResolutionOf(planted, <DartPackage>[
        planted,
        DartPackage(directory: sibling.path, name: 'tool_plugin'),
      ]);
      expect(read, hasLength(1), reason: 'a package names itself and every cache entry too');
      expect(read.single.name, 'tool_plugin');
      expect(sameDirectory(read.single.root, sibling.path), isTrue);
    });

    test('a package nothing has resolved answers with nothing rather than with an assumption', () {
      final Directory scratch = Directory.systemTemp.createTempSync('hostyour-cloud-unresolved-');
      addTearDown(() => scratch.deleteSync(recursive: true));
      expect(
        inRepositoryResolutionOf(
          DartPackage(directory: scratch.path, name: 'planted'),
          const <DartPackage>[],
        ),
        isEmpty,
        reason: 'its pub get failing is the gate\'s own finding, and it is already reported there',
      );
    });
  });
}
