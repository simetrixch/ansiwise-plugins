import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Gives an identity provider's administrator group its rights on this cluster.
///
/// The other half of the API server's OIDC wiring, and neither half works alone. The server's
/// arguments make the cluster accept a token issued by the identity provider; this says what the
/// person behind that token may do. Without it a login succeeds, the token is accepted, and every
/// call comes back forbidden — which reads as a broken dashboard and is a missing binding.
///
/// **The group name carries the prefix the API server was told to add.** The cluster does not see
/// the group the identity provider issued; it sees that name with the prefix in front of it, and a
/// binding written without the prefix matches nobody. The two are set together on purpose, which is
/// why the prefix is required here: it has to be the same word the server's arguments name, and
/// that word belongs to the installation, not to this step.
///
/// **The binding is replaced rather than edited.** A binding whose subjects or role drifted is
/// removed and written again, because the parts of it that decide who gets cluster-wide rights are
/// exactly the parts a partial edit would leave half changed.
final class OidcAdminsBinding extends ReversibleStep<bool> {
  /// Binds [group], as the identity provider issues it, to [clusterRole].
  const OidcAdminsBinding({
    required this.name,
    required this.group,
    required this.groupsPrefix,
    required this.clusterRole,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory OidcAdminsBinding.fromArguments(Arguments arguments) => OidcAdminsBinding(
    name: arguments.text('name'),
    group: arguments.text('group'),
    groupsPrefix: arguments.text('groups_prefix'),
    clusterRole: arguments.text('cluster_role'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the name of the binding on the cluster',
    ),
    ArgumentSpec(
      name: 'group',
      kind: ArgumentKind.text,
      describes: 'the group as the identity provider issues it, without any prefix',
    ),
    ArgumentSpec(
      name: 'groups_prefix',
      kind: ArgumentKind.text,
      describes:
          'the prefix the API server adds to every group it reads out of a token, which the '
          'binding has to carry or it matches nobody — the same word the server\'s own arguments '
          'were configured with, which may be empty where the server adds none',
    ),
    ArgumentSpec(
      name: 'cluster_role',
      kind: ArgumentKind.text,
      describes: 'the role that group is given',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The binding's name.
  final String name;

  /// The group, as the identity provider issues it.
  final String group;

  /// The prefix the API server adds.
  final String groupsPrefix;

  /// The role the group is given.
  final String clusterRole;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// The group name as the cluster sees it.
  String get prefixedGroup => '$groupsPrefix$group';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult read = await context.shell.run(
      kubectl.observing(<String>['get', 'clusterrolebinding', name, '-o', 'json']),
    );
    if (!read.ok) {
      return const CheckResult.ready();
    }

    final Object? decoded = _decoded(read.trimmed);
    if (decoded is! Map<String, Object?>) {
      return const CheckResult.ready();
    }
    final Object? roleRef = decoded['roleRef'];
    final Object? subjects = decoded['subjects'];
    if (roleRef is! Map<String, Object?> || subjects is! List<Object?>) {
      return const CheckResult.ready();
    }
    if (roleRef['name'] != clusterRole) {
      return const CheckResult.ready();
    }

    final bool bound = subjects.any(
      (Object? subject) =>
          subject is Map<String, Object?> &&
          subject['kind'] == 'Group' &&
          subject['name'] == prefixedGroup,
    );
    return bound
        ? CheckResult.satisfied('$prefixedGroup is bound to $clusterRole by $name')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(kubectl.argv(_create));

  @override
  Future<void> apply(StepContext context) async {
    // Removed first, because a binding whose role or subjects drifted cannot be edited into the
    // right shape by a create, and the parts that drift are the parts that decide who holds
    // cluster-wide rights.
    await context.shell.run(
      kubectl.command(<String>['delete', 'clusterrolebinding', name, '--ignore-not-found']),
    );
    final CommandResult created = await context.shell.run(kubectl.command(_create));
    if (!created.ok) {
      throw CommandFailed(
        argv: kubectl.argv(_create),
        exitCode: created.exitCode,
        stdout: '',
        stderr: created.stderr,
      );
    }
  }

  /// Whether the cluster already holds a ClusterRoleBinding called [name].
  ///
  /// Read before the apply, which removes the binding and writes it again — after that the name is
  /// taken either way, and the undo would be taking away a grant that was standing before this run
  /// started. What that binding gave to whom is not captured: putting an object back means applying
  /// it, and this step has no file to apply, it composes its binding out of its own arguments with
  /// `kubectl create`. So the undo removes a binding this run created, and leaves one it replaced.
  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult read = await context.shell.run(
      kubectl.observing(<String>['get', 'clusterrolebinding', name, '-o', 'name']),
    );
    return read.ok;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      kubectl.command(<String>['delete', 'clusterrolebinding', name, '--ignore-not-found']),
    );
  }

  List<String> get _create => <String>[
    'create',
    'clusterrolebinding',
    name,
    '--clusterrole=$clusterRole',
    '--group=$prefixedGroup',
  ];

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
