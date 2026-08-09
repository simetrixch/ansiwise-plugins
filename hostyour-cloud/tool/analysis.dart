/// The analyzer and the formatter, over every Dart package of this repository.
///
/// ```
/// dart run tool/analysis.dart
/// ```
///
/// A program and not a test, because a test is compiled by the analysis it is meant to fail on: the
/// day the package stops analysing, a test that judged it would be the thing that did not compile.
/// What CAN be a test is the proof that this reads the two tools correctly, and that lives in
/// test/checks/analysis_check_test.dart — with a fake toolchain for the parsing and the real one over
/// a scratch package for the day either tool changes what it writes.
library;

import 'dart:io';

import 'gate/analysis_check.dart';
import 'gate/dart_packages.dart';
import 'gate/paths.dart';
import 'gate/real_dart_toolchain.dart';

Future<void> main() async {
  // The REPOSITORY and not the package this program sits in. The first line of this file has always
  // said "over every Dart package of this repository"; while there was one package the two were the
  // same directory and the difference could not show. It showed the moment a second arrived.
  final Directory repository = repositoryOf(packageOfToolScript(Platform.script));
  final List<DartPackage> packages = dartPackagesIn(repository);
  if (packages.isEmpty) {
    stderr.writeln('analysis: FAIL — no Dart package under ${repository.path} to judge');
    exit(1);
  }

  final AnalysisReading reading = await AnalysisCheck(
    toolchain: const RealDartToolchain(),
    packages: packages,
  ).run();

  for (final AnalysisIssue issue in reading.issues) {
    stdout.writeln('  finding: $issue');
  }
  for (final String name in reading.notAnalysed) {
    stdout.writeln(
      '  NOT ANALYSED: $name — nothing here resolved its dependencies, so the analyzer would answer '
      'with one error per import and nothing about the code. Resolving it with the SDK its own '
      'pubspec asks for is what opens it to this check.',
    );
  }

  if (reading.green) {
    stdout.writeln(reading.verdictLine);
    return;
  }
  stderr.writeln(reading.verdictLine);
  exitCode = 1;
}
