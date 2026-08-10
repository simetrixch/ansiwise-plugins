/// Which copy of each package of this repository the checks were actually answered against.
///
/// THE DEFECT THIS EXISTS FOR. The product plugin names the five tool packages by a git ref, and
/// both the override file and the lock file are gitignored. Without the untracked override the
/// composition is resolved OUT OF A COMMIT, while each tool package's own checks walk the working
/// tree beside it — so one half of the gate judges the bytes on disk, the other half judges bytes
/// from a commit, and the verdict is green across the split. Only a path-level disagreement is
/// loud: a step whose body changed and whose name did not produces no output at all.
///
/// WHY REFUSING RATHER THAN NAMING THE REVISION. The other way out is to print which revision of
/// each package was measured, and it does not close this. The working tree HAS no revision — it is
/// a commit plus whatever is uncommitted, which is the whole reason somebody is running the gate —
/// so a verdict naming a commit for one half and "the working tree" for the other would state the
/// split accurately and let it stand. What the gate is asked is whether this tree is finishable,
/// and it cannot answer that about a composition built from something other than this tree. So a
/// package of this repository that resolved anywhere but to its checkout in this repository is a
/// refusal, and the log names, for every package, where each of them came from.
///
/// HOW IT IS READ. `dart pub get` writes `.dart_tool/package_config.json` beside the package, and
/// every entry of it carries a `rootUri` relative to that file. Whatever answered — a path
/// override, a git ref, the pub cache — the resolved directory is in there, which makes this the
/// one place that says what was really compiled rather than what a manifest asked for.
///
/// It imports nothing but `dart:`, like everything else the gate reaches before `dart pub get`.
library;

import 'dart:convert';
import 'dart:io';

import 'dart_packages.dart';

/// Where one package resolved one dependency to.
final class ResolvedDependency {
  /// Records that [inPackage] resolved [name] to the directory [root].
  const ResolvedDependency({required this.inPackage, required this.name, required this.root});

  /// The package whose resolution this is.
  final String inPackage;

  /// The name of the dependency, as an import says it after `package:`.
  final String name;

  /// The directory it resolved to, as this operating system names it.
  final String root;

  @override
  String toString() => '$inPackage resolved $name from $root';
}

/// Every dependency of [package] that this repository also holds on disk, and where it came from.
///
/// A dependency this repository does not hold is not listed: it resolves through the pub cache by
/// design, and nothing here judges it. An unresolved package answers with nothing, which is what a
/// package whose `pub get` failed is — and that failure is already the gate's own finding.
List<ResolvedDependency> inRepositoryResolutionOf(
  DartPackage package,
  List<DartPackage> repositoryPackages,
) {
  final File config = File('${package.directory}/.dart_tool/package_config.json');
  if (!config.existsSync()) {
    return const <ResolvedDependency>[];
  }
  final Map<String, String> heldHere = <String, String>{
    for (final DartPackage held in repositoryPackages) held.name: held.directory,
  };
  final Object? read = jsonDecode(config.readAsStringSync());
  if (read is! Map<String, Object?>) {
    return const <ResolvedDependency>[];
  }
  final Object? entries = read['packages'];
  if (entries is! List<Object?>) {
    return const <ResolvedDependency>[];
  }
  final List<ResolvedDependency> found = <ResolvedDependency>[];
  for (final Object? entry in entries) {
    if (entry is! Map<String, Object?>) {
      continue;
    }
    final Object? name = entry['name'];
    final Object? rootUri = entry['rootUri'];
    if (name is! String || rootUri is! String || !heldHere.containsKey(name)) {
      continue;
    }
    // A package never resolves itself somewhere else, and listing it would say nothing.
    if (name == package.name) {
      continue;
    }
    found.add(
      ResolvedDependency(
        inPackage: package.name,
        name: name,
        root: _directoryNamedBy(rootUri, from: '${package.directory}/.dart_tool/'),
      ),
    );
  }
  found.sort((ResolvedDependency a, ResolvedDependency b) => a.name.compareTo(b.name));
  return found;
}

/// Every resolution of [resolutions] that came from outside this repository's own checkouts.
///
/// The refusal names the package, the dependency, where it came from and where it should have come
/// from — the four things somebody needs to write the override file that fixes it.
List<String> splitResolutions({
  required List<ResolvedDependency> resolutions,
  required List<DartPackage> repositoryPackages,
}) {
  final Map<String, String> heldHere = <String, String>{
    for (final DartPackage held in repositoryPackages) held.name: held.directory,
  };
  return <String>[
    for (final ResolvedDependency resolved in resolutions)
      if (heldHere[resolved.name] case final String checkout)
        if (!sameDirectory(resolved.root, checkout))
          '${resolved.inPackage} was composed from ${resolved.name} at ${resolved.root}, and the '
              'checks of ${resolved.name} judge $checkout — two different copies, so a green '
              'verdict is green about neither',
  ];
}

/// Whether [one] and [other] name the same directory.
///
/// Separators and a trailing one are how the same directory comes to be written two ways: a package
/// config carries a URI and the walk carries what this operating system wrote. Case is compared
/// exactly, because a path that differs only in case is a different path on the machine the product
/// runs on, and the gate is not the place to start treating the two as one.
bool sameDirectory(String one, String other) => _flattened(one) == _flattened(other);

String _flattened(String path) {
  final String forward = path.replaceAll(r'\', '/');
  return forward.endsWith('/') ? forward.substring(0, forward.length - 1) : forward;
}

/// The directory [rootUri] names, resolved against [from].
String _directoryNamedBy(String rootUri, {required String from}) {
  final Uri base = Uri.directory(from, windows: Platform.isWindows);
  return Directory.fromUri(base.resolveUri(Uri.parse(rootUri))).absolute.path;
}
