/// How the analyzer and the formatter are started, as values a probe can drive.
///
/// WHY THIS IS NOT SIMPLY INLINE IN analysis.dart. The argument list and the working directory ARE
/// the check. Two edits leave every test green and the gate blind: drop `--fatal-infos`, and every
/// info becomes invisible — which is where this project's strictness lives, since strict-casts,
/// strict-inference and strict-raw-types all report at info; or point the run at a directory holding
/// no Dart, where `dart analyze` exits zero and says "No issues found".
///
/// Neither is caught by anything that parses output, because nothing is wrong with the output. So
/// the invocation is a value here, and test/analysis_invocation_test.dart runs the REAL tools
/// against a planted package to prove that this argument list goes red where a weakened one does
/// not — and that a directory with nothing to judge is refused rather than reported clean.
library;

import 'dart:io';

/// The analyzer, with the two flags that make it decide rather than describe.
///
/// `--fatal-infos` is not a preference. The analysis options of this package turn on strict casts,
/// strict inference and strict raw types, and every one of them reports at INFO — so without this
/// flag the package's whole strictness setting is advisory.
const List<String> analyzerArgv = <String>['analyze', '--fatal-infos', '--fatal-warnings'];

/// The formatter, writing nothing.
///
/// `--output=none` so a red run leaves the tree exactly as it found it: a check that repaired what
/// it measures would be green the second time for having changed the thing it judged.
const List<String> formatterArgv = <String>[
  'format',
  '--output=none',
  '--set-exit-if-changed',
  '.',
];

/// Whether [directory] holds any Dart at all, at any depth.
///
/// `dart analyze` answers "No issues found" for a directory with nothing in it, and exits zero. A
/// gate that took that for a verdict would report a clean package every time somebody pointed it one
/// level too high — which is the failure this exists to make impossible.
bool holdsDart(Directory directory) {
  if (!directory.existsSync()) {
    return false;
  }
  for (final FileSystemEntity entry in directory.listSync(recursive: true, followLinks: false)) {
    if (entry is File && entry.path.endsWith('.dart')) {
      return true;
    }
  }
  return false;
}

/// Runs `dart [argv]` in [directory] and answers its exit status.
///
/// The SDK is [Platform.resolvedExecutable] and never the word `dart` on the PATH, so the tools that
/// answer are the ones the toolchain guard just read the version of.
Future<int> runDart(List<String> argv, {required String directory, bool quiet = false}) async {
  final Process process = await Process.start(
    Platform.resolvedExecutable,
    argv,
    workingDirectory: directory,
    mode: quiet ? ProcessStartMode.normal : ProcessStartMode.inheritStdio,
  );
  if (quiet) {
    await process.stdout.drain<void>();
    await process.stderr.drain<void>();
  }
  return process.exitCode;
}
