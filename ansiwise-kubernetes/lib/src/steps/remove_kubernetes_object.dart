import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Takes the objects of one manifest off the cluster — and ONLY where every one of them carries the
/// ownership label the row states.
///
/// **The label is the whole safety of this step, and it is required rather than offered.** A
/// removal is aimed by NAME, and a name can collide: an object of the same kind and name that
/// something else created — a platform's own project, a hand-made resource — must never be taken
/// away on the strength of that collision. So whatever created the object marks it with a label,
/// and this step refuses to delete anything not carrying that mark. An unguarded delete is not this
/// step's to offer — it exists as the ordinary object step's undo, which only ever removes what
/// that same run created.
///
/// **Absence is read off the cluster, never assumed.** The check asks for the manifest's objects;
/// a cluster holding none of them is already in the state this step produces. What this asks with
/// is one read of the whole manifest, so a manifest of SEVERAL documents is judged whole: partially
/// present objects read as absent, which errs toward leaving things standing — never toward
/// deleting something the guard did not see.
final class RemoveKubernetesObject extends IrreversibleStep {
  /// Removes the labeled objects of the manifest at [manifest], under [repository].
  const RemoveKubernetesObject({
    required this.repository,
    required this.manifest,
    required this.ownerLabel,
    required this.ownerLabelValue,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory RemoveKubernetesObject.fromArguments(Arguments arguments) => RemoveKubernetesObject(
    repository: arguments.text('repository'),
    manifest: arguments.text('manifest'),
    ownerLabel: arguments.text('owner_label'),
    ownerLabelValue: arguments.text('owner_label_value'),
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
      describes: 'the manifest naming the objects to remove, as a path under that checkout',
    ),
    ArgumentSpec(
      name: 'owner_label',
      kind: ArgumentKind.text,
      describes:
          'the key of the label the objects must carry to be removable at all — the mark whatever '
          'created them put on them. An object of the same name NOT carrying it with '
          'owner_label_value belongs to something else, and this step refuses it rather than '
          'deleting on a name collision',
    ),
    ArgumentSpec(
      name: 'owner_label_value',
      kind: ArgumentKind.text,
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

  /// The key of the label the objects must carry.
  final String ownerLabel;

  /// The value that label must hold.
  final String ownerLabelValue;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Whether the manifest file belongs to root, so reading it is elevated.
  final bool elevated;

  /// The manifest as the machine holds it.
  String get path => '$repository/$manifest';

  @override
  String get irreversibleReason =>
      'what the objects held beyond the manifest — their status, whatever reconciled against them '
      '— is state nothing wrote down, and applying the manifest again makes new objects rather '
      'than bringing that back';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (ownerLabel.isEmpty || ownerLabelValue.isEmpty) {
      return const CheckResult.blocked(
        'the ownership label needs both halves — without them there is no mark to hold the '
        'objects against, and an unguarded delete is not this step\'s to perform',
      );
    }
    if (!await context.files.exists(path, elevated: elevated)) {
      return CheckResult.blocked(
        '$manifest is not in this checkout, so there is nothing naming what to remove',
      );
    }
    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['get', '--filename', path, '-o', 'json']),
    );
    if (found.exitCode != 0) {
      return CheckResult.satisfied(
        'the cluster holds none of the objects $manifest names — already removed',
      );
    }
    final String? unmarked = _firstUnmarked(found.stdout);
    if (unmarked != null) {
      return CheckResult.blocked(
        '$unmarked exists WITHOUT the label $ownerLabel=$ownerLabelValue — it belongs to '
        'something else, and this removal refuses a name collision rather than deleting what it '
        'never created',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_delete);

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult removed = await context.shell.run(
      kubectl.command(<String>['delete', '--filename', path, '--ignore-not-found']),
    );
    if (!removed.ok) {
      throw CommandFailed(
        argv: _delete,
        exitCode: removed.exitCode,
        stdout: '',
        stderr: removed.stderr,
      );
    }
  }

  /// The first live object of the manifest that does NOT carry the ownership label, named for the
  /// refusal, or null when every one carries it.
  String? _firstUnmarked(String listing) {
    final Object? decoded = _decoded(listing);
    if (decoded is! Map<String, Object?>) {
      // An answer nobody can read must not pass for "all marked": erring that way deletes on a
      // listing the guard never saw.
      return 'an object whose listing could not be read';
    }
    final Object? items = decoded['items'];
    final List<Object?> objects = items is List<Object?> ? items : <Object?>[decoded];
    for (final Object? object in objects) {
      if (object is! Map<String, Object?>) {
        continue;
      }
      final Object? metadata = object['metadata'];
      final Object? labels = metadata is Map<String, Object?> ? metadata['labels'] : null;
      final Object? marked = labels is Map<String, Object?> ? labels[ownerLabel] : null;
      if (marked != ownerLabelValue) {
        final Object? kind = object['kind'];
        final Object? name = metadata is Map<String, Object?> ? metadata['name'] : null;
        return '$kind "$name"';
      }
    }
    return null;
  }

  List<String> get _delete =>
      kubectl.argv(<String>['delete', '--filename', path, '--ignore-not-found']);

  /// [text] as JSON, or null when it is not.
  static Object? _decoded(String text) {
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
