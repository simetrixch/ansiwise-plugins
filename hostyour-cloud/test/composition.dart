// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io' show Directory, Platform;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';

/// Where the installation this plugin deploys keeps its configuration.
///
/// **The programs are not this package's.** A program file says what THIS installation deploys and
/// in what order, so it lives in the installation's own repository beside the things it names — the
/// binary reads it from a directory at run time (`--programs`, and its refusal says "run this where
/// the installation is"). What this package ships is the steps a program may name.
///
/// **The tests still prove the programs, because a program that does not resolve is caught here or
/// on a machine.** So they read the tree next to this checkout, and the environment may point them
/// somewhere else.
String get installationTree =>
    Platform.environment['ANSIWISE_INSTALLATION'] ?? '../../../digitaplatform/digita-cloud';

/// [installationTree], proven to be there.
///
/// **Absent FAILS, and says what it looked for.** A test suite that quietly skipped the programs
/// would report green over the one thing it is here to measure — and the shape of that failure is a
/// program with a misspelled step name reaching a machine.
String get installationRoot {
  if (!Directory('$installationTree/$installationPrograms').existsSync()) {
    throw StateError(
      'no programs at $installationTree/$installationPrograms — the programs of an installation '
      'live in its own repository, and these tests read that tree. Clone it beside this one, or '
      'set ANSIWISE_INSTALLATION to where it is.',
    );
  }
  return installationTree;
}

/// Where the programs stand inside an installation tree.
const String installationPrograms = 'ansiwise/programs';

/// The program file named [name], as a path a test can open.
String programAt(String name) => '$installationRoot/$installationPrograms/$name';

/// The registry a program of this product is actually resolved against.
///
/// **Not this package's own registry.** The steps a program names come from five plugins now — the
/// four tool packages and this product on top of them — and a test that resolved a program against
/// this package alone would report every step of the other four as unregistered. Worse, once that
/// test were made to pass by narrowing what it checks, it would prove a program correct against a
/// set of steps nobody ships.
///
/// **The active list is read from the shipped configuration and not written here.** `ansiwise.yaml`
/// is what an installation turns on, so a plugin dropped from that file has to break the programs
/// that use its steps — which is exactly what these tests are for.
Future<Registry> shippedRegistry() async {
  // The real reader, because the file being read is the one that ships. A fake here would prove a
  // composition against text a test wrote.
  final Configuration active = await Configuration.load(
    files: const RealFiles(),
    path: Configuration.defaultFileName,
  );
  return compiledPlugins.activate(active.plugins);
}
