import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/analysis_check.dart';
import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/real_dart_toolchain.dart';

/// The counter-probe of the check that cannot be a test of this package.
///
/// tool/analysis.dart judges the package this file is compiled into, so it is a program rather than a
/// test: a test would be compiled by the analysis it is meant to fail on, and the day the package
/// stops analysing the check meant to say so is the thing that did not compile.
///
/// What is left over is everything that CAN be proven without judging this package, and it is in two
/// halves. The first hands the check an answer and reads what it decided; it needs no toolchain, and
/// it is what catches a rule that stopped matching the shape either tool writes. The second runs the
/// REAL analyzer and the REAL formatter over a package written here, each carrying one defect, and
/// asserts that both go red on it and silent on its clean neighbour. A green gate over a repository
/// nobody looked at is what a check rots into, and the only thing that rules it out is watching the
/// tools report something.
void main() {
  group('what the check makes of an answer', () {
    test('the analyzer output is read one issue per line', () {
      expect(
        analyzerIssuesIn(
          const ToolRun(
            exitCode: 3,
            output:
                'Analyzing planted...\n'
                '  error - lib/planted.dart:2:19 - A value of type String cannot be assigned - '
                'invalid_assignment\n'
                '   info - lib/planted.dart:3:3 - Unused import - unused_import\n'
                '2 issues found.\n',
          ),
        ),
        hasLength(2),
        reason: 'the analyzer writes a header and a count around its issues, and neither is one',
      );
    });

    test('a clean analyzer run reports nothing', () {
      expect(
        analyzerIssuesIn(
          const ToolRun(exitCode: 0, output: 'Analyzing planted...\nNo issues found!\n'),
        ),
        isEmpty,
        reason: 'this rule reports every line, so it would turn every package red',
      );
    });

    test('the formatter output names the files it would change', () {
      expect(
        formatterChangesIn(
          const ToolRun(
            exitCode: 1,
            output: 'Changed lib/planted.dart\nFormatted 3 files (1 changed) in 0.04 seconds.\n',
          ),
        ),
        <String>['lib/planted.dart'],
        reason: 'the summary line is not a change, and the changed file is what a person opens',
      );
    });

    test('an unresolved package is not analysed and is named for it', () async {
      final DartPackage package = _package(_scratch('unresolved'), 'planted_unresolved');
      final AnalysisReading reading = await AnalysisCheck(
        toolchain: FakeDartToolchain(
          answers: <String, ToolRun>{
            'analyze': const ToolRun(
              exitCode: 3,
              output:
                  '  error - lib/a.dart:1:8 - Target of URI does not exist - uri_does_not_exist\n',
            ),
          },
        ),
        packages: <DartPackage>[package],
      ).run();

      expect(reading.notAnalysed, <String>['planted_unresolved']);
      expect(
        reading.issues,
        isEmpty,
        reason:
            'the analyzer answers a package it cannot resolve with one error per import and nothing '
            'about the code, which is the one answer nobody can act on',
      );
      expect(reading.verdictLine, contains('NOT ANALYSED'));
    });

    test('a resolved package is analysed, and the formatter reads it either way', () async {
      final DartPackage package = _package(
        _scratch('resolved'),
        'planted_resolved',
        resolved: true,
      );
      final FakeDartToolchain toolchain = FakeDartToolchain(
        answers: <String, ToolRun>{
          'analyze': const ToolRun(
            exitCode: 3,
            output: '  error - lib/a.dart:2:19 - A value of type String - invalid_assignment\n',
          ),
          'format': const ToolRun(exitCode: 1, output: 'Changed lib/a.dart\n'),
        },
      );
      final AnalysisReading reading = await AnalysisCheck(
        toolchain: toolchain,
        packages: <DartPackage>[package],
      ).run();

      expect(reading.analysed, <String>['planted_resolved']);
      expect(reading.issues, hasLength(2));
      expect(reading.green, isFalse);
      expect(
        toolchain.calls.map((ToolCall call) => call.what),
        containsAll(<String>['analyze', 'format']),
      );
    });

    test('a clean reading says what it proved and about how many packages', () {
      const AnalysisReading reading = AnalysisReading(
        issues: <AnalysisIssue>[],
        analysed: <String>['planted_resolved'],
        notAnalysed: <String>[],
      );
      expect(reading.green, isTrue);
      expect(reading.verdictLine, startsWith('analysis: OK — '));
      expect(reading.verdictLine, contains('all 1 Dart package(s)'));
    });
  });

  group('counter-probe: the real tools still go red', () {
    late Directory broken;
    late Directory clean;

    setUpAll(() {
      broken = Directory.systemTemp.createTempSync('hostyour-cloud-analysis-broken-');
      clean = Directory.systemTemp.createTempSync('hostyour-cloud-analysis-clean-');
      Directory('${broken.path}/lib').createSync(recursive: true);
      Directory('${clean.path}/lib').createSync(recursive: true);
      File('${broken.path}/pubspec.yaml').writeAsStringSync('name: planted_unresolved\n');
      File('${clean.path}/pubspec.yaml').writeAsStringSync('name: planted_resolved\n');
      File('${clean.path}/lib/planted.dart').writeAsStringSync(_formattedAndSound);
    });

    tearDownAll(() {
      broken.deleteSync(recursive: true);
      clean.deleteSync(recursive: true);
    });

    test('a planted assignment of text to an int is reported', () async {
      File('${broken.path}/lib/planted.dart').writeAsStringSync(_theAnalyzerRefusesThis);
      expect(
        analyzerIssuesIn(await const RealDartToolchain().analyze(directory: broken.path)),
        isNotEmpty,
        reason: 'this check cannot go red on the analyzer, so its silence means nothing',
      );
    });

    test('a file with nothing wrong in it is not reported', () async {
      expect(
        analyzerIssuesIn(await const RealDartToolchain().analyze(directory: clean.path)),
        isEmpty,
        reason: 'this check would turn every package red',
      );
    });

    test('a deliberately unformatted file is reported', () async {
      File('${broken.path}/lib/planted.dart').writeAsStringSync(_theFormatterWouldRewriteThis);
      expect(
        formatterChangesIn(await const RealDartToolchain().format(directory: broken.path)),
        isNotEmpty,
        reason: 'this check cannot go red on the formatter',
      );
    });

    test('an already formatted file is not reported as needing a change', () async {
      expect(
        formatterChangesIn(await const RealDartToolchain().format(directory: clean.path)),
        isEmpty,
      );
    });
  });

  group('counter-probe: the resolution test, from both sides', () {
    // Only the second half has teeth in a tree where everything is resolved: a rule that called every
    // package unresolved would report a green analysis over a tree it never looked at, which is the
    // shape this whole escape hatch could rot into.

    test('a package no reachable config names is called unresolved', () {
      expect(
        packageIsResolved(_package(_scratch('no-config'), 'planted_unresolved')),
        isFalse,
        reason: 'an unanalysable package would be reported as a tree full of defects',
      );
    });

    test('a package its own config names is called resolved', () {
      expect(
        packageIsResolved(_package(_scratch('own-config'), 'planted_resolved', resolved: true)),
        isTrue,
        reason: 'this check would stop analysing everything',
      );
    });

    test('the nearest config above a directory is the one that applies', () {
      final Directory scratch = _scratch('nearest');
      Directory('${scratch.path}/member/lib').createSync(recursive: true);
      Directory('${scratch.path}/.dart_tool').createSync(recursive: true);
      File('${scratch.path}/.dart_tool/package_config.json').writeAsStringSync('{}');
      expect(
        packageConfigFor('${scratch.path}/member')?.path,
        startsWith(scratch.path),
        reason:
            'a workspace member has no config of its own, and one resolution at the workspace root '
            'covers every member',
      );
    });
  });

  group('the invocation, which the probes above do not reach', () {
    // The real-tools group already plants a fault and watches the analyzer report it — but what it
    // plants is an assignment of text to an int, and that is an ERROR. An error is reported whatever
    // flags the run carries, so every one of those probes stays green with `--fatal-infos` removed.
    // And removing it is exactly the edit that matters: strict casts, strict inference and strict
    // raw types all report at INFO, so without the flag the whole strictness setting of this
    // repository is advisory and nothing anywhere says so.
    //
    // So the fault planted here reports at info, and the same tree is judged TWICE — with the flag
    // and without. "It went red" proves nothing until the weakened invocation is shown to go green
    // on the very same tree.

    late Directory onlyAnInfo;

    setUpAll(() {
      onlyAnInfo = Directory.systemTemp.createTempSync('hostyour-cloud-info-');
      Directory('${onlyAnInfo.path}/lib').createSync(recursive: true);
      File('${onlyAnInfo.path}/pubspec.yaml').writeAsStringSync('name: planted_info\n');
      // One lint, enabled outright, so the planted package needs no dependency in order to resolve.
      // A lint reports at info, which is the level this repository's strictness settings report at.
      File(
        '${onlyAnInfo.path}/analysis_options.yaml',
      ).writeAsStringSync('linter:\n  rules:\n    - prefer_single_quotes\n');
      File(
        '${onlyAnInfo.path}/lib/planted.dart',
      ).writeAsStringSync('const String planted = "double";\n');
    });

    tearDownAll(() => onlyAnInfo.deleteSync(recursive: true));

    test('a fault that only reports at info turns the analyzer red', () async {
      final ToolRun run = await const RealDartToolchain().analyze(directory: onlyAnInfo.path);
      expect(
        run.exitCode,
        isNot(0),
        reason:
            'this is the fault class strict casts, strict inference and strict raw types all '
            'produce, and the one the flag exists for',
      );
    });

    test('and the same tree passes once --fatal-infos is taken away', () async {
      final Process weakened = await Process.start(Platform.resolvedExecutable, <String>[
        for (final String argument in RealDartToolchain.analyzerArgv)
          if (argument != '--fatal-infos') argument,
      ], workingDirectory: onlyAnInfo.path);
      await weakened.stdout.drain<void>();
      await weakened.stderr.drain<void>();
      expect(
        await weakened.exitCode,
        0,
        reason:
            'one flag fewer and the fault is gone from the verdict — which is why dropping it is a '
            'silent edit, and why nothing above could have caught it',
      );
    });

    test('the analyzer really is started with both flags', () {
      expect(
        RealDartToolchain.analyzerArgv,
        containsAll(<String>['--fatal-infos', '--fatal-warnings']),
      );
    });

    test('the formatter writes nothing and reports a difference', () {
      expect(
        RealDartToolchain.formatterArgv,
        containsAll(<String>['--output=none', '--set-exit-if-changed']),
        reason:
            'a check that repaired what it measures would be green the second time for having '
            'changed the thing it judged',
      );
    });
  });
}

Directory _scratch(String name) {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-analysis-$name-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}

DartPackage _package(Directory directory, String name, {bool resolved = false}) {
  File('${directory.path}/pubspec.yaml').writeAsStringSync('name: $name\n');
  if (resolved) {
    Directory('${directory.path}/.dart_tool').createSync(recursive: true);
    File('${directory.path}/.dart_tool/package_config.json').writeAsStringSync(
      '{ "configVersion": 2, "packages": [ { "name": "$name", "rootUri": "../" } ] }',
    );
  }
  return DartPackage(directory: directory.path, name: name);
}

const String _theAnalyzerRefusesThis =
    'void main() {\n'
    '  final int planted = "this is text, and the analyzer refuses the assignment";\n'
    '  print(planted);\n'
    '}\n';

const String _theFormatterWouldRewriteThis = 'void main(){int   planted=1;print(planted);}\n';

const String _formattedAndSound = 'void main() {\n  print(1);\n}\n';
