/// Compiling the binary that gets copied to a machine.
///
/// The client reaches a fresh Ubuntu with a username and a password and nothing else on it — no
/// Dart, no checkout. So what travels is one self-contained executable, and this is where it comes
/// from.
///
/// The composition root lives with the plugin set it composes: Dart ahead of time loads no code that
/// was not compiled in, so which plugins EXIST is decided by what the entry point imports, and which
/// are ACTIVE is decided by the `ansiwise.yaml` the binary reads on the machine.
library;

import 'dart:io';

import 'dart_toolchain.dart';

/// What building the binary came to.
sealed class BuildOutcome {
  const BuildOutcome();
}

/// It compiled, and this is where it landed.
final class Built extends BuildOutcome {
  /// Records the artifact at [target], compiled by [toolVersion].
  const Built(this.target, this.toolVersion);

  /// Where the executable is.
  final String target;

  /// What compiled it, so a binary on a machine can be traced back to an SDK.
  final String toolVersion;

  @override
  String toString() => 'built $target ($toolVersion)';
}

/// It did not compile.
final class BuildFailed extends BuildOutcome {
  /// Records what the compiler said.
  const BuildFailed(this.why);

  /// What came back.
  final String why;

  @override
  String toString() => 'the build failed: $why';
}

/// The build of one package's entry point.
final class BinaryBuild {
  /// Compiles [entryPoint] of [package] with [toolchain].
  const BinaryBuild({
    required this.toolchain,
    required this.package,
    this.entryPoint = 'bin/ansiwise.dart',
  });

  /// How the compiler is started.
  final DartToolchain toolchain;

  /// The package holding the composition root.
  final String package;

  /// The composition root, relative to [package].
  final String entryPoint;

  /// Compiles to [target], relative to [package].
  ///
  /// The default output goes to `build/` and not to `bin/`, which holds the composition root's
  /// source. An artifact beside the source it was compiled from is one `git add` away from being
  /// committed.
  Future<BuildOutcome> to(String target) async {
    File('$package/$target').parent.createSync(recursive: true);
    final ToolRun compiled = await toolchain.compileExecutable(
      directory: package,
      entryPoint: entryPoint,
      target: target,
    );
    if (!compiled.succeeded) {
      return BuildFailed(compiled.output.trim());
    }
    final ToolRun version = await toolchain.version(directory: package);
    return Built(target, _sdkVersion(version.output));
  }
}

/// The version out of what `dart --version` wrote.
String _sdkVersion(String output) {
  final RegExpMatch? match = RegExp(r'Dart SDK version:\s*(\S+)').firstMatch(output);
  return match?.group(1) ?? output.trim();
}
