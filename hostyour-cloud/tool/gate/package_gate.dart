/// Every check of every Dart package in this tree, and one verdict.
///
/// Nothing here starts a tool itself: it is handed a toolchain and a list of packages, which is what
/// lets a test drive the whole sequence and read the verdict without `dart` being involved.
///
/// Each package is resolved, then the analyzer and the formatter are asked about the whole tree at
/// once, then each suite runs. A package whose resolution failed is not analysed and not tested —
/// there is nothing true to say about it until its dependencies are there, and the analyzer would
/// answer with one error per import.
///
/// EVERY PACKAGE AND EVERY STEP RUNS EVEN AFTER AN EARLIER ONE WENT RED. One failure hiding the rest
/// is how the next run finds a second problem that was there all along.
library;

import 'dart:io';

import 'dart_packages.dart';
import 'dart_toolchain.dart';
import 'gate_log.dart';

/// What a gate run decided.
final class GateVerdict {
  /// Records the steps that went red, as `<package>/<step>`.
  const GateVerdict(this.failures);

  /// What failed, in the order it failed.
  final List<String> failures;

  /// Whether everything passed.
  bool get green => failures.isEmpty;

  /// The one line the gate is read by.
  String get line => green ? 'ci: OK — every check green' : 'ci: FAIL — ${failures.join(' ')}';
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

    return GateVerdict(failures);
  }
}
