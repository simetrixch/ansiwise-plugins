import 'dart:io';

import 'package:test/test.dart';

import '../../tool/gate/dart_packages.dart';
import '../../tool/gate/dart_toolchain.dart';
import '../../tool/gate/fake_dart_toolchain.dart';
import '../../tool/gate/gate_log.dart';
import '../../tool/gate/package_gate.dart';

/// The check sequence of the gate, driven against a scripted toolchain.
///
/// The verdict line is the one thing a person reads off a gate run, and everything below decides it.
/// A package whose resolution failed must not be analysed or tested — the analyzer answers such a
/// package with one error per import and the failure reads as a tree full of defects — and every
/// remaining package must still run, because one failure hiding the rest is how the next run finds a
/// second problem that was there all along.
void main() {
  test('a green run says exactly what the gate is read by', () async {
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>['one']).run();
    expect(verdict.green, isTrue);
    expect(verdict.line, 'ci: OK — every check green for 1 package(s): one');
  });

  test('the green line names every package it covered', () async {
    // The count and the names are in the line the reader takes the verdict from, not only in the
    // log above it. This gate has already printed `every check green` over a package it never
    // opened: a second one arrived in the repository and the walk was still rooted at the first.
    // A number a reader knows is what turns that from invisible into obvious.
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>['one', 'two']).run();
    expect(verdict.line, 'ci: OK — every check green for 2 package(s): one, two');
  });

  test('a run that found no package is not green', () async {
    final GateVerdict verdict = await _gate(FakeDartToolchain(), <String>[]).run();
    expect(
      verdict.line,
      'ci: FAIL — no Dart package was found to check, so nothing was measured',
      reason:
          'there is no such thing as every check passing when no check ran, and a gate pointed at '
          'the wrong directory is exactly how that happens',
    );
  });

  test('every package is resolved, analysed once, and tested', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain();
    await _gate(toolchain, <String>['one', 'two']).run();
    expect(
      toolchain.calls.map((ToolCall call) => call.what),
      <String>['pub get', 'pub get', 'run tool/analysis.dart', 'test', 'test'],
      reason:
          'one analysis run covers every package, so it is started once and only after every '
          'resolution',
    );
  });

  test('a package whose resolution failed is named, and not analysed or tested', () async {
    final List<DartPackage> packages = _packages(<String>['one', 'two']);
    final FakeDartToolchain toolchain = FakeDartToolchain(
      answers: <String, ToolRun>{
        'pub get in ${packages.first.directory}': const ToolRun(
          exitCode: 69,
          output: 'could not resolve',
        ),
      },
    );
    final GateVerdict verdict = await PackageGate(
      toolchain: toolchain,
      packages: packages,
      log: CollectedGateLog(),
      analysisRoot: '/work',
    ).run();

    expect(verdict.failures, <String>['one/pub-get']);
    expect(verdict.line, 'ci: FAIL — one/pub-get');
    expect(
      toolchain.calls
          .where((ToolCall call) => call.what == 'test')
          .map((ToolCall call) => call.directory),
      <String>[packages.last.directory],
      reason: 'a package with no dependencies resolved has nothing true to say about itself',
    );
  });

  test('a red analysis is named on its own, because it is one run over every package', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain()..streamedExitCode = 1;
    final GateVerdict verdict = await _gate(toolchain, <String>['one']).run();
    expect(verdict.failures, contains('analysis'));
  });

  test('a red suite names the package it was in', () async {
    final FakeDartToolchain toolchain = FakeDartToolchain()..streamedExitCode = 1;
    final GateVerdict verdict = await _gate(toolchain, <String>['one']).run();
    expect(verdict.failures, contains('one/test'));
  });

  test(
    'a package with no test directory is said to have none rather than passing quietly',
    () async {
      final Directory scratch = _scratch();
      final DartPackage package = DartPackage(
        directory: '${scratch.path}/untested',
        name: 'untested',
      );
      Directory(package.directory).createSync(recursive: true);
      final CollectedGateLog log = CollectedGateLog();
      final GateVerdict verdict = await PackageGate(
        toolchain: FakeDartToolchain(),
        packages: <DartPackage>[package],
        log: log,
        analysisRoot: scratch.path,
      ).run();

      expect(verdict.green, isTrue);
      expect(log.said, contains('no test/ directory in untested'));
    },
  );
}

PackageGate _gate(FakeDartToolchain toolchain, List<String> names) => PackageGate(
  toolchain: toolchain,
  packages: _packages(names),
  log: CollectedGateLog(),
  analysisRoot: '/work',
);

/// One scratch package per name, in that order, each carrying the test/ directory that makes a suite
/// run.
List<DartPackage> _packages(List<String> names) {
  final Directory scratch = _scratch();
  final List<DartPackage> packages = <DartPackage>[];
  for (final String name in names) {
    Directory('${scratch.path}/$name/test').createSync(recursive: true);
    packages.add(DartPackage(directory: '${scratch.path}/$name', name: name));
  }
  return packages;
}

Directory _scratch() {
  final Directory directory = Directory.systemTemp.createTempSync('hostyour-cloud-package-gate-');
  addTearDown(() => directory.deleteSync(recursive: true));
  return directory;
}
