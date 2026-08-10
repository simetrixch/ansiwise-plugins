/// Every package that carries a suite says what it checks, and carries the check that reads it.
///
/// THE HOLE THIS CLOSES, AND WHY IT IS NOT THE SAME ONE. `dart test` discovers whatever is on disk:
/// delete a check file and nothing fails, because the check is not there to fail, and the run goes
/// on to report that every check is green. Each package answers that with `checks.yaml` and a check
/// that holds the declaration against the disk, naming whatever vanished.
///
/// That check cannot notice its own absence. A check and its counter-probe live in one file, so
/// deleting `declared_checks_test.dart` takes the reading with it and leaves `checks.yaml` describing
/// a suite nobody compares anything to. So the gate asks the one question the suite cannot: are the
/// two files there.
///
/// IT DOES NOT READ THE DECLARATION, AND THAT IS DELIBERATE. The reading is one implementation, in
/// package:ansiwise_checks, driven by every package's own suite. Nothing under tool/ may import a
/// package — `dart pub get` is the gate's first step, so the gate has to start on a clone where
/// nothing is resolved — and a second reader written here would be a second answer that can disagree
/// with the one that decides.
library;

import 'dart:io';

import 'dart_packages.dart';

/// Where a package declares what it checks, relative to its root.
const String checksFile = 'checks.yaml';

/// The check that reads that declaration and holds the disk against it.
const String declaredChecksGuard = 'declared_checks_test.dart';

/// Every package of [packages] that carries a suite and is missing one of the two, as a refusal.
///
/// A package with no `test/` at all is not judged here: it has no suite, so there is nothing for a
/// declaration to be held against — and the gate already says out loud that such a package was not
/// tested.
List<String> undeclaredSuites(List<DartPackage> packages) {
  final List<String> refusals = <String>[];
  for (final DartPackage package in packages) {
    if (!Directory('${package.directory}/test').existsSync()) {
      continue;
    }
    final String directory = checksDirectoryOf(package);
    for (final String path in <String>[checksFile, '$directory/$declaredChecksGuard']) {
      if (!File('${package.directory}/$path').existsSync()) {
        refusals.add(
          '${package.name} has no $path, so nothing holds its suite to what it says it checks — '
          'a check deleted there takes its own counter-probe with it and the run stays green',
        );
      }
    }
  }
  return refusals;
}

/// Where [package] keeps the files that judge it as a package.
///
/// A package that is nothing BUT checks keeps them directly under `test/`; one that also has the
/// ordinary tests of its own steps keeps them apart, in a directory of their own, and only those are
/// declared. The directory on disk is what says which of the two this is.
String checksDirectoryOf(DartPackage package) =>
    Directory('${package.directory}/test/checks').existsSync() ? 'test/checks' : 'test';
