/// analysis — the analyzer and the formatter are clean for every Dart package.
///
/// `dart analyze --fatal-infos --fatal-warnings` with this repository's analysis_options is not a
/// style pass. strict-casts, strict-inference and strict-raw-types are on, so an implicit cast, an
/// inferred `dynamic` and a raw generic are each a type the author never chose and each stops the
/// build; unused_import, unused_local_variable and dead_code are raised to errors, which is the
/// no-leftovers rule of this project enforced by a tool rather than by a reviewer. `dart format
/// --set-exit-if-changed` is what keeps a diff about the change instead of about the whitespace.
///
/// THIS CANNOT BE A TEST OF THE PACKAGE IT JUDGES. A test is compiled by the analysis it is meant to
/// fail on, so the day the package stops analysing, the check meant to say so is the thing that did
/// not compile. It is a program the gate runs instead — `dart run tool/analysis.dart` — and that is
/// bash-free without being a test.
///
/// A PACKAGE WHOSE DEPENDENCIES ARE NOT RESOLVED IS NOT ANALYSED, AND IS NAMED FOR IT. The analyzer
/// answers a package it cannot resolve with one error per import and then hundreds more about every
/// name those imports would have brought in — a missing toolchain reported as a tree full of
/// defects, which is the one answer nobody can act on. So the package config that applies is read
/// first, and a package it does not cover is reported NOT ANALYSED with its name on the verdict
/// line. That is a gap and it is meant to read as one; it is not a pass.
library;

import 'dart:io';

import 'dart_packages.dart';
import 'dart_toolchain.dart';

/// One thing the analyzer or the formatter reported about a package.
final class AnalysisIssue {
  /// Records an issue in [package].
  const AnalysisIssue(this.package, this.what);

  /// The package it is about, as the gate names it.
  final String package;

  /// What the tool said, in its own words.
  final String what;

  @override
  String toString() => '$package: $what';
}

/// What the analyzer and the formatter made of a set of packages.
final class AnalysisReading {
  /// Records what each package turned out to be.
  const AnalysisReading({required this.issues, required this.analysed, required this.notAnalysed});

  /// Everything the two tools reported.
  final List<AnalysisIssue> issues;

  /// The packages whose dependencies were resolved, so the analyzer could say something true.
  final List<String> analysed;

  /// The packages nothing here resolved, named because a gap has to read as one.
  final List<String> notAnalysed;

  /// Whether the tools found nothing.
  bool get green => issues.isEmpty;

  /// What this run decided, in the one line a person reads.
  String get verdictLine {
    if (!green) {
      return 'analysis: FAIL — ${issues.length} issue(s) above';
    }
    final String gap = notAnalysed.isEmpty
        ? ''
        : ', and ${notAnalysed.length} was NOT ANALYSED — ${notAnalysed.join(', ')} — because '
              'nothing here resolved its dependencies, though the formatter still read it';
    return 'analysis: OK — dart analyze --fatal-infos --fatal-warnings and dart format '
        '--output=none --set-exit-if-changed are clean for all ${analysed.length} Dart package(s) '
        'whose dependencies are resolved here$gap';
  }
}

/// The check itself, over the packages and the toolchain it is given.
final class AnalysisCheck {
  /// Asks [toolchain] about each of [packages].
  const AnalysisCheck({required this.toolchain, required this.packages});

  /// How the two tools are started.
  final DartToolchain toolchain;

  /// What is judged.
  final List<DartPackage> packages;

  /// Runs both tools over every package.
  Future<AnalysisReading> run() async {
    final List<AnalysisIssue> issues = <AnalysisIssue>[];
    final List<String> analysed = <String>[];
    final List<String> notAnalysed = <String>[];

    for (final DartPackage package in packages) {
      if (packageIsResolved(package)) {
        analysed.add(package.name);
        for (final String issue in analyzerIssuesIn(
          await toolchain.analyze(directory: package.directory),
        )) {
          issues.add(AnalysisIssue(package.name, issue));
        }
      } else {
        notAnalysed.add(package.name);
      }

      // The formatter parses and never resolves, so it holds for a package whose dependencies are
      // missing exactly as it does for one that has them. An unresolved package is unanalysed, not
      // unchecked.
      for (final String changed in formatterChangesIn(
        await toolchain.format(directory: package.directory),
      )) {
        issues.add(AnalysisIssue(package.name, 'dart format would change $changed'));
      }
    }

    return AnalysisReading(issues: issues, analysed: analysed, notAnalysed: notAnalysed);
  }
}

/// Every issue in what the analyzer wrote, one per line.
///
/// The exit status is not read: the analyzer answers 1, 2 and 3 for different severities and 0 for a
/// run that found nothing, and what this reports is the issues themselves.
List<String> analyzerIssuesIn(ToolRun run) => <String>[
  for (final String line in run.output.split('\n'))
    if (_issueLine.hasMatch(line)) line.trim(),
];

/// Every file the formatter would change, one per line.
List<String> formatterChangesIn(ToolRun run) => <String>[
  for (final String line in run.output.split('\n'))
    if (_changedLine.firstMatch(line.trimRight())?.group(1) case final String path) path,
];

/// Whether the package config that applies to [package] knows [package].
///
/// A config that does not know the package cannot know its dependencies either, so every import in
/// it is unresolved and every issue the analyzer would report is about that and nothing else.
bool packageIsResolved(DartPackage package) {
  final File? config = packageConfigFor(package.directory);
  if (config == null) {
    return false;
  }
  return configNamesPackage(config.readAsStringSync(), package.name);
}

/// The package config the analyzer would use for [directory]: the nearest one at or above it.
///
/// This is the analyzer's own rule, and following it is what lets the answer above be about the same
/// files the analyzer will read. A workspace member has none of its own — one resolution at the
/// workspace root covers every member — and a package that resolves on its own has one beside it.
File? packageConfigFor(String directory) {
  Directory current = Directory(directory).absolute;
  while (true) {
    final File config = File('${current.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      return config;
    }
    final Directory parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

/// Whether [configText] names [packageName] among the packages it resolves.
bool configNamesPackage(String configText, String packageName) =>
    RegExp('"name"\\s*:\\s*"${RegExp.escape(packageName)}"').hasMatch(configText);

final RegExp _issueLine = RegExp(r'^\s*(error|warning|info) - ');
final RegExp _changedLine = RegExp(r'^Changed (.+)$');
