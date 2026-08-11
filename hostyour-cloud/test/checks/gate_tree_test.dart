import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/binary_build.dart';
import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/paths.dart';

/// The two things the gate does to a tree: find the packages in it and compile the binary out of it
/// — plus the path arithmetic it does for itself, because nothing under tool/ may import
/// package:path and a wrong answer there points the toolchain at the wrong directory.
void main() {
  group('the path arithmetic tool/ does without package:path', () {
    test('a program under tool/ finds the package it is part of', () {
      expect(
        packageOfToolScript(Uri.file('/repos/hostyour-cloud/tool/ci.dart')).path,
        endsWith('hostyour-cloud'),
        reason:
            'taken from where the program sits and not from the working directory, so a run from a '
            'subdirectory answers the same instead of quietly gating less',
      );
    });

    test('the last segment is found whichever separator wrote the path', () {
      expect(baseName(r'D:\repos\hostyour-cloud\tool'), 'tool');
      expect(baseName('/work/hostyour-cloud/tool'), 'tool');
    });

    test('the repository is the directory holding .git, not the package below it', () {
      // The distinction the gate could not make. While this repository held ONE package the two were
      // the same directory; a second arrived, the walk was still rooted at the first, and the run
      // printed `every check green` over sixty-four files it had never opened.
      final Directory scratch = _scratch();
      Directory('${scratch.path}/.git').createSync(recursive: true);
      final Directory package = Directory('${scratch.path}/a-package/tool')
        ..createSync(recursive: true);
      expect(repositoryOf(package).path, scratch.absolute.path);
    });

    test('a directory under no repository is refused rather than guessed at', () {
      // Answering with SOMETHING — the filesystem root, or the directory it started from — would
      // send the gate over a tree nobody named, and let it report about that one in exactly the
      // words it reports about ours.
      expect(
        () => repositoryOf(_scratch()),
        throwsA(
          isA<StateError>().having(
            (StateError e) => e.message,
            'message',
            contains('no .git at or above'),
          ),
        ),
      );
    });
  });

  group('finding the packages', () {
    test('a package at the root of a tree that carries code is one', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/lib').createSync(recursive: true);
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_root\n');
      expect(
        dartPackagesIn(scratch).map((DartPackage package) => package.name),
        <String>['planted_root'],
        reason: 'a one-package repository would otherwise be invisible to every check',
      );
    });

    test('a manifest at the root of a tree with no code is a workspace and is not one', () {
      final Directory scratch = _scratch();
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_workspace\n');
      Directory('${scratch.path}/member/lib').createSync(recursive: true);
      File('${scratch.path}/member/pubspec.yaml').writeAsStringSync('name: planted_member\n');
      expect(
        dartPackagesIn(scratch).map((DartPackage package) => package.name),
        <String>['planted_member'],
        reason: 'walking a workspace manifest as a package counts every member twice',
      );
    });

    test('a manifest under a pruned directory is not a package of this tree', () {
      final Directory scratch = _scratch();
      Directory('${scratch.path}/lib').createSync(recursive: true);
      File('${scratch.path}/pubspec.yaml').writeAsStringSync('name: planted_root\n');
      Directory('${scratch.path}/.dart_tool/planted').createSync(recursive: true);
      File('${scratch.path}/.dart_tool/planted/pubspec.yaml').writeAsStringSync('name: resolved\n');
      expect(dartPackagesIn(scratch), hasLength(1));
    });

    test('the name comes from the manifest and not from the directory', () {
      expect(
        declaredPackageName('# a comment\nname: hostyour_cloud\nversion: 0.1.0\n'),
        'hostyour_cloud',
        reason: 'the directory is hostyour-cloud, and a Dart package name may not carry a hyphen',
      );
    });
  });

  group('compiling the binary', () {
    test('the composition root is what is compiled, and it lands outside bin/', () async {
      final Directory scratch = _scratch();
      final FakeDartToolchain toolchain = FakeDartToolchain(
        answers: <String, ToolRun>{
          '--version': const ToolRun(exitCode: 0, output: 'Dart SDK version: 3.12.2 (stable)\n'),
        },
      );
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: toolchain,
        package: scratch.path,
      ).to('build/ansiwise');

      expect(outcome, isA<Built>());
      expect((outcome as Built).toolVersion, '3.12.2');
      expect(
        toolchain.calls.map((ToolCall call) => call.what),
        contains('compile bin/ansiwise.dart -> build/ansiwise'),
      );
      expect(
        Directory('${scratch.path}/build').existsSync(),
        isTrue,
        reason: 'the compiler writes no directory of its own, so a missing one is a failed build',
      );
    });

    test('a compiler that refused says why, rather than reporting a binary nobody has', () async {
      final BuildOutcome outcome = await BinaryBuild(
        toolchain: FakeDartToolchain(
          answers: <String, ToolRun>{
            'compile bin/ansiwise.dart -> build/ansiwise': const ToolRun(
              exitCode: 254,
              output: 'Error: something in the composition root does not compile',
            ),
          },
        ),
        package: _scratch().path,
      ).to('build/ansiwise');

      expect(outcome, isA<BuildFailed>());
      expect((outcome as BuildFailed).why, contains('does not compile'));
    });
  });
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-tool-tree-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
