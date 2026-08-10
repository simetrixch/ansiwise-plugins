/// Every check of every Dart package in this tree, and one verdict.
///
/// Nothing here starts a tool itself: it is handed a toolchain and a list of packages, which is what
/// lets a test drive the whole sequence and read the verdict without `dart` being involved.
///
/// Each package is resolved, then what each of them resolved a package of this repository TO is
/// read and refused where it is not this repository's own checkout, then the analyzer and the
/// formatter are asked about the whole tree at once, then each suite runs. A package whose
/// resolution failed is not analysed and not tested — there is nothing true to say about it until
/// its dependencies are there, and the analyzer would answer with one error per import.
///
/// EVERY PACKAGE AND EVERY STEP RUNS EVEN AFTER AN EARLIER ONE WENT RED. One failure hiding the rest
/// is how the next run finds a second problem that was there all along.
library;

import 'dart:io';

import 'dart_packages.dart';
import 'dart_toolchain.dart';
import 'gate_log.dart';
import 'resolved_packages.dart';

/// What a gate run decided.
final class GateVerdict {
  /// Records the steps that went red, as `<package>/<step>`, out of [covered] packages.
  const GateVerdict(this.failures, {required this.covered});

  /// What failed, in the order it failed.
  final List<String> failures;

  /// The packages this run went through, by name and in the order it took them.
  ///
  /// Carried into the verdict rather than left to the log above it, because the green line is the
  /// one thing anybody reads and `every check green` says nothing about how much was looked at. This
  /// gate has already once printed exactly that over a package it never opened, when a second one
  /// arrived in the repository and the walk was still rooted at the first.
  final List<String> covered;

  /// Whether everything passed.
  bool get green => failures.isEmpty;

  /// The one line the gate is read by.
  ///
  /// It names what it covered, so the reader can hold the claim against a count he knows instead of
  /// taking it. A run that covered nothing says so and is not green: there is no such thing as every
  /// check passing when no check ran.
  String get line {
    if (covered.isEmpty) {
      return 'ci: FAIL — no Dart package was found to check, so nothing was measured';
    }
    return green
        ? 'ci: OK — every check green for ${covered.length} package(s): ${covered.join(', ')}'
        : 'ci: FAIL — ${failures.join(' ')}';
  }
}

/// The checks of every package, run in order.
final class PackageGate {
  /// Runs [packages] through [toolchain], announcing each step on [log].
  const PackageGate({
    required this.toolchain,
    required this.packages,
    required this.log,
    required this.analysisRoot,
    this.analysisScript = 'tool/analysis.dart',
  });

  /// How the tools are started.
  final DartToolchain toolchain;

  /// What is checked.
  final List<DartPackage> packages;

  /// Where the gate says what it is doing.
  final GateLog log;

  /// The package the analyzer check is started from.
  ///
  /// One run covers every package, so it is started once and from the repository rather than per
  /// package.
  final String analysisRoot;

  /// The program that judges the analyzer and the formatter.
  final String analysisScript;

  /// Runs everything and answers with what went red.
  Future<GateVerdict> run() async {
    final List<String> failures = <String>[];
    final List<DartPackage> resolved = <DartPackage>[];

    for (final DartPackage package in packages) {
      log.heading('${package.name} — dart pub get');
      final ToolRun run = await toolchain.pubGet(directory: package.directory);
      log.note(run.output.trimRight());
      if (run.succeeded) {
        resolved.add(package);
      } else {
        failures.add('${package.name}/pub-get');
      }
    }

    // WHICH COPY OF EACH PACKAGE WAS COMPOSED, before anything is judged. A package of this
    // repository that a sibling resolved from a commit or a cache is a second copy of code this
    // gate is also walking on disk, and the two halves of the run would then be green about
    // different bytes. Read after every resolution, because that is when the package config says
    // what really answered.
    log.heading('resolved packages');
    for (final DartPackage package in resolved) {
      for (final ResolvedDependency dependency in inRepositoryResolutionOf(package, packages)) {
        log.note('  $dependency');
      }
    }
    final List<String> split = splitResolutions(
      resolutions: <ResolvedDependency>[
        for (final DartPackage package in resolved) ...inRepositoryResolutionOf(package, packages),
      ],
      repositoryPackages: packages,
    );
    if (split.isNotEmpty) {
      for (final String refusal in split) {
        log.note('  $refusal');
      }
      failures.add('resolution');
    }

    log.heading('dart run $analysisScript');
    if (await toolchain.runScript(analysisScript, directory: analysisRoot) != 0) {
      failures.add('analysis');
    }

    for (final DartPackage package in resolved) {
      if (!Directory('${package.directory}/test').existsSync()) {
        log.note('no test/ directory in ${package.name}');
        continue;
      }
      log.heading('${package.name} — dart test');
      if (await toolchain.runTests(directory: package.directory) != 0) {
        failures.add('${package.name}/test');
      }
    }

    return GateVerdict(
      failures,
      covered: <String>[for (final DartPackage package in packages) package.name],
    );
  }
}
