import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

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
    this.ownerLabel,
    this.ownerLabelValue,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory KubernetesObject.fromArguments(Arguments arguments) => KubernetesObject(
    repository: arguments.text('repository'),
    manifest: arguments.text('manifest'),
    ownerLabel: arguments.optionalText('owner_label'),
    ownerLabelValue: arguments.optionalText('owner_label_value'),
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
    ArgumentSpec(
      name: 'owner_label',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the key of the label that marks the manifest\'s objects as this program\'s to rewrite. '
          'Stated, a live object of the same name NOT carrying it with owner_label_value is '
          'refused rather than applied over — it belongs to something else, and a name collision '
          'must not hand its contents to this manifest. The manifest itself must carry the label, '
          'or the object it applies would refuse its own next run',
    ),
    ArgumentSpec(
      name: 'owner_label_value',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the value the ownership label must hold — the other half of owner_label',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The checkout.
  final String repository;

  /// The manifest, relative to it.
  final String manifest;

  /// The key of the label marking the manifest's objects as this program's to rewrite, or null
  /// where the row states none.
  final String? ownerLabel;

  /// The value that label must hold, or null where the row states no label.
  final String? ownerLabelValue;

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
    if (await _collision(context) case final String collision) {
      return CheckResult.blocked(collision);
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

  /// Why a live object of this manifest may not be applied over, or null when every one may.
  ///
  /// Asked only where the row states an owner label. A live object carrying the label is this
  /// program's from an earlier run; one WITHOUT it belongs to something else, and applying this
  /// manifest would hand that object's contents to a file that merely shares its name. Objects the
  /// cluster does not hold collide with nothing.
  Future<String?> _collision(StepContext context) async {
    final String? key = ownerLabel;
    if (key == null) {
      return null;
    }
    final String? value = ownerLabelValue;
    if (value == null || value.isEmpty) {
      return 'owner_label names $key and no owner_label_value says what it must hold — without '
          'both halves there is no mark to hold the live objects against';
    }

    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['get', '--filename', path, '-o', 'json']),
    );
    if (found.exitCode != 0) {
      // Nothing (or not everything) of the manifest is live — nothing here can collide.
      return null;
    }
    final Object? decoded = _decodedJson(found.stdout);
    if (decoded is! Map<String, Object?>) {
      return 'the live objects of $manifest could not be read while holding them against the '
          'label $key=$value — an unreadable listing must not pass for "all marked"';
    }
    final Object? items = decoded['items'];
    final List<Object?> objects = items is List<Object?> ? items : <Object?>[decoded];
    for (final Object? object in objects) {
      if (object is! Map<String, Object?>) {
        continue;
      }
      final Object? metadata = object['metadata'];
      final Object? labels = metadata is Map<String, Object?> ? metadata['labels'] : null;
      final Object? marked = labels is Map<String, Object?> ? labels[key] : null;
      if (marked != value) {
        final Object? kind = object['kind'];
        final Object? name = metadata is Map<String, Object?> ? metadata['name'] : null;
        return '$kind "$name" exists WITHOUT the label $key=$value — it belongs to something '
            'else, and applying this manifest over it would hand its contents to a file that '
            'merely shares its name';
      }
    }
    return null;
  }

  /// [text] as JSON, or null when it is not.
  static Object? _decodedJson(String text) {
    if (text.trim().isEmpty) {
      return null;
    }
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }
}
