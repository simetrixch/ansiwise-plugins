/// analysis — the analyzer and the formatter, over the gate package.
///
/// `dart analyze --fatal-infos --fatal-warnings` with this package's analysis_options is not a
/// style pass. strict-casts, strict-inference and strict-raw-types are on, so an implicit cast, an
/// inferred `dynamic` and a raw generic are each a type the author never chose and each stops the
/// run; unused_import, unused_local_variable and dead_code are raised to errors, which is the
/// no-leftovers rule of this project enforced by a tool rather than by a reviewer.
/// `dart format --set-exit-if-changed` is what keeps a diff about the change instead of about the
/// whitespace.
///
/// THIS IS THE ONE CHECK THAT CANNOT BE A `dart test`. A test runs inside the package it would
/// judge, so it is compiled by the very analysis it is meant to fail on: either the package
/// analyses, and the test has nothing to report, or it does not, and the test never starts.
/// Everything else lives under test/ and arrives with the suite.
///
/// NOTHING HERE PARSES OUTPUT — each tool's exit status IS the verdict — and that used to be given
/// as the reason this check needed no counter-probe. It was the wrong reason. It covers the OUTPUT
/// and not the INVOCATION, and the invocation is where two silent edits live: drop `--fatal-infos`
/// and every info goes invisible, which is exactly where this package's strictness sits; or point
/// the run at a directory holding no Dart, where `dart analyze` exits zero and says "No issues
/// found". Neither leaves anything wrong in the output for a parser to miss.
///
/// So the argument lists are values in tool/analysis_invocation.dart, and
/// test/analysis_invocation_test.dart runs the real tools against a planted package to prove that
/// this invocation goes red where a weakened one does not.
///
/// `--output=none` writes nothing, so a red run leaves the tree exactly as it found it: a check
/// that repaired what it measures would be green the second time for having changed the thing it
/// judged.
///
///     dart run tool/analysis.dart
library;

import 'dart:io';

import 'analysis_invocation.dart';

Future<void> main() async {
  final Directory package = File.fromUri(Platform.script).parent.parent;

  // Before either tool runs. `dart analyze` in a directory with nothing in it exits zero and reports
  // no issues, so a run pointed one level too high would come back clean about a package it never
  // opened — the same shape of wrong answer as a gate that walked a package where it meant a
  // repository.
  if (!holdsDart(package)) {
    stderr.writeln('analysis: FAIL — no Dart under ${package.path}, so nothing was judged');
    exit(1);
  }

  for (final List<String> argv in <List<String>>[analyzerArgv, formatterArgv]) {
    stdout.writeln('analysis: dart ${argv.join(' ')}');
    final int status = await runDart(argv, directory: package.path);
    if (status != 0) {
      stderr.writeln('analysis: FAIL — dart ${argv.first} exited $status');
      exit(1);
    }
  }

  stdout.writeln('analysis: OK — the gate package analyses clean and is formatted');
}
