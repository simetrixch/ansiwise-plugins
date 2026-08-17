import 'package:ansiwise_api/ansiwise_api.dart';

import 'kubectl.dart';

/// Puts the objects of one manifest of the checkout on the cluster, and takes exactly those away.
///
/// **One step for every manifest, because applying a file is one act.** Certificates, routes,
/// transports, middleware, bindings — whatever a manifest declares, putting it on the cluster is
/// the same act, and what differs between manifests is a path. A path is an argument, so what would
/// otherwise be a step class per object kind is a row per file.
///
/// **Applied and not created, so a second run is a no-op the API server decides.** `kubectl apply`
/// is declarative: it sends the manifest and the server works out whether anything changes. That is
/// what makes this step repeatable without reading the cluster first and comparing — a comparison
/// this step could get wrong in a way the server cannot.
///
/// **The check asks whether the objects are there, and never what they hold.** A manifest in the
/// checkout holds no credential, so the reason is not secrecy: it is that the file is the truth and
/// the cluster is where it is put. A step that compared them would be answering "has somebody edited
/// this object by hand", which is a question for a drift report and not for a deployment.
///
/// **The undo removes the objects this manifest names and nothing else.** `kubectl delete
/// --filename` reads the same file, so what is removed is exactly what was applied — including on a
/// manifest holding several objects, where a delete by kind and name would need the step to parse
/// the file and would drift from it the moment somebody added a document. It removes them only where
/// [capture] found the cluster holding none of them.
final class KubernetesObject extends ReversibleStep<bool> {
  /// Applies the manifest at [manifest], under [repository].
  const KubernetesObject({
    required this.repository,
    required this.manifest,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory KubernetesObject.fromArguments(Arguments arguments) => KubernetesObject(
    repository: arguments.text('repository'),
    manifest: arguments.text('manifest'),
    kubectl: Kubectl.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the manifest is read from',
    ),
    ArgumentSpec(
      name: 'manifest',
      kind: ArgumentKind.text,
      describes: 'the manifest, as a path under that checkout',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The checkout.
  final String repository;

  /// The manifest, relative to it.
  final String manifest;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// The manifest as the machine holds it.
  String get path => '$repository/$manifest';

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(path, elevated: elevated)) {
      // Blocked and not failed: the tree is what it is, and no run can write this file. Saying which
      // path is missing is the whole of what an operator needs.
      return CheckResult.blocked('$manifest is not in this checkout, so there is nothing to apply');
    }
    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['diff', '--filename', path]),
    );
    // `kubectl diff` exits zero when the cluster already holds what the file says and one when it
    // does not — which is the question this step's check asks, answered by the server rather than by
    // a comparison of our own. Anything above one is the command failing, and a failure to measure
    // is not the same as work to do.
    return switch (found.exitCode) {
      0 => CheckResult.satisfied(
        'the objects of $manifest are on this cluster as the file has them',
      ),
      1 => const CheckResult.ready(),
      _ => CheckResult.blocked('the cluster could not be asked about $manifest: ${found.stderr}'),
    };
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_apply);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult applied = await context.shell.run(
      kubectl.command(<String>['apply', '--filename', path]),
    );
    if (!applied.ok) {
      throw CommandFailed(
        argv: _apply,
        exitCode: applied.exitCode,
        stdout: '',
        stderr: applied.stderr,
      );
    }
  }

  /// Whether the cluster already holds every object [manifest] names.
  ///
  /// Read before the apply, because `kubectl delete --filename` removes what the file names whether
  /// or not this run put it there. One answer for the whole manifest, because the delete is one act
  /// on the whole file: there is no half of it to take back.
  ///
  /// What those objects held before is not captured. The cluster answers with the object as it
  /// stands, resourceVersion and all, and applying that again is refused as a conflict once anything
  /// has changed the object since — which the apply of this step does. So an object that was already
  /// there is left carrying what this run applied.
  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['get', '--filename', path, '-o', 'name']),
    );
    return found.ok;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      kubectl.command(<String>['delete', '--filename', path, '--ignore-not-found']),
    );
  }

  List<String> get _apply => kubectl.argv(<String>['apply', '--filename', path]);
}
