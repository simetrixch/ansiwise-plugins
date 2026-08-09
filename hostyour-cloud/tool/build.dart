/// Compiles the binary that gets copied to a machine.
///
/// ```
/// dart run tool/build.dart              to build/ansiwise
/// dart run tool/build.dart <target>     to a path of your own, relative to this package
/// ```
library;

import 'dart:io';

import 'gate/binary_build.dart';
import 'gate/paths.dart';
import 'gate/real_dart_toolchain.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length > 1) {
    stderr.writeln('build: FAIL — expected at most one argument, the target path');
    exit(2);
  }

  final BinaryBuild build = BinaryBuild(
    toolchain: const RealDartToolchain(),
    package: packageOfToolScript(Platform.script).path,
  );

  switch (await build.to(arguments.isEmpty ? defaultTarget : arguments.single)) {
    case Built(:final String target, :final String toolVersion):
      stdout.writeln('built $target ($toolVersion)');
    case BuildFailed(:final String why):
      stderr.writeln('build: FAIL — $why');
      exitCode = 1;
  }
}

/// Where the executable lands when nobody says otherwise.
const String defaultTarget = 'build/ansiwise';
