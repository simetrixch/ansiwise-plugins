import 'dart:io';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_checks/ansiwise_checks.dart';
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
///
/// **Where that tree is, is decided ONCE and not here.** The five tool packages this plugin stands
/// on read the same declarations for the same reason — their probes plant the kinds and defaults the
/// programs declare — and a second answer to "where is the installation" is a second answer that can
/// disagree with the first. So the resolution and its refusal come out of the checks package, and
/// are carried on through here for everything that already reads them.
export 'package:ansiwise_checks/ansiwise_checks.dart'
    show installationPrograms, installationProgramsRoot, installationRoot, programAt;

/// The registry a program of this product is actually resolved against.
///
/// **Not this package's own registry.** The steps a program names come from five plugins now — the
/// five tool packages and this product on top of them — and a test that resolved a program against
/// this package alone would report every step of the other four as unregistered. Worse, once that
/// test were made to pass by narrowing what it checks, it would prove a program correct against a
/// set of steps nobody ships.
///
/// **The active list is read from the INSTALLATION and not written here.** `ansiwise.yaml` says
/// which plugins an installation turns on, which makes it that installation's configuration and not
/// this package's — it lives beside the programs it decides the steps for, and the binary reads it
/// out of the directory it is run in. A plugin dropped from that file has to break the programs that
/// use its steps, and that is exactly what these tests are for.
Future<Registry> shippedRegistry() async {
  // The real reader, because the file being read is the one that ships. A fake here would prove a
  // composition against text a test wrote.
  final Configuration active = await Configuration.load(
    files: const RealFiles(),
    path: '$installationRoot/${Configuration.defaultFileName}',
  );
  return compiledPlugins.activate(active.plugins);
}

/// The environment variable that names the tree an installation deploys, overriding the fallback.
const String deployedTreeVariable = 'ANSIWISE_DEPLOYED_TREE';

/// The tree an installation deploys, as the environment names it or as a checkout sits beside this
/// one.
///
/// **Not the installation's tree and not this package's.** Three trees take part in a deployment and
/// they are three repositories: this plugin ships the steps, the installation ships the programs and
/// the answers, and the deployed tree ships the charts and the manifests a cluster renders. The
/// second is already resolved for every package that reads answer declarations; this is the third,
/// and it is resolved HERE rather than beside it, because only this product deploys that tree — a
/// tool package would be naming an application of its tool.
///
/// **What it is for.** Several facts of this product live on BOTH sides and can drift apart with
/// nothing reporting it: a Vault role a chart presents against the role a program creates, a key a
/// step writes against the key a chart reads, a template a step fills against the template the tree
/// ships. Every one of those was a defect found by hand, and each half was tested against a fixture
/// its own author had typed.
///
/// **It is TEST INPUT and says so.** Nothing in this package's library is derived from it, and no
/// step reads it — the deployed tree reaches a machine as a checkout at a path a program names.
String get deployedTree => Platform.environment[deployedTreeVariable] ?? '../../hostyour-cloud';

/// [deployedTree], proven to be there.
///
/// Absent FAILS rather than skips. A suite that quietly passed over the second half of a two-sided
/// fact would report green on exactly the drift it exists to catch.
String get deployedRoot {
  if (!Directory('$deployedTree/charts').existsSync()) {
    throw StateError(
      'no charts at $deployedTree/charts — the tree an installation deploys lives in its own '
      'repository, and these tests read it for the half of a fact this package does not hold. '
      'Clone it beside this one, or set $deployedTreeVariable to where it is.',
    );
  }
  return deployedTree;
}
