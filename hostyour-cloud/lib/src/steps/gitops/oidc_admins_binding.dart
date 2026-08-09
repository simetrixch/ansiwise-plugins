import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Gives the identity provider's administrator group its rights on this cluster.
///
/// The other half of the API server wiring, and neither half works alone. The arguments make the
/// cluster accept a token issued by the identity provider; this says what the person behind that
/// token may do. Without it a login succeeds, the token is accepted, and every call comes back
/// forbidden — which reads as a broken dashboard and is a missing binding.
///
/// **The group name carries the prefix the API server was told to add.** The cluster does not see
/// the group the identity provider issued; it sees that name with the prefix in front of it, and a
/// binding written without the prefix matches nobody. The two are set together on purpose.
///
/// **The binding is replaced rather than edited.** A binding whose subjects or role drifted is
/// removed and written again, because the parts of it that decide who gets cluster-wide rights are
/// exactly the parts a partial edit would leave half changed.
final class OidcAdminsBinding extends ReversibleStep {
  /// Binds [group], as the identity provider issues it, to [clusterRole].
  const OidcAdminsBinding({
    required this.name,
    required this.group,
    required this.groupsPrefix,
    required this.clusterRole,
  });

  /// Builds the step from what the program gave it.
  factory OidcAdminsBinding.fromArguments(Arguments arguments) => OidcAdminsBinding(
    name: arguments.text('name'),
    group: arguments.text('group'),
    groupsPrefix: arguments.text('groups_prefix'),
    clusterRole: arguments.text('cluster_role'),
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
      defaultValue: 'oidc:',
      describes:
          'the prefix the API server adds to every group it reads out of a token, which the '
          'binding has to carry or it matches nobody',
    ),
    ArgumentSpec(
      name: 'cluster_role',
      kind: ArgumentKind.text,
      describes: 'the role that group is given',
    ),
  ];

  /// The binding's name.
  final String name;

  /// The group, as the identity provider issues it.
  final String group;

  /// The prefix the API server adds.
  final String groupsPrefix;

  /// The role the group is given.
  final String clusterRole;

  /// The group name as the cluster sees it.
  String get prefixedGroup => '$groupsPrefix$group';

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult read = await context.shell.run(
      Command.observing('kubectl', <String>['get', 'clusterrolebinding', name, '-o', 'json']),
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
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(_create);

  @override
  Future<void> apply(StepContext context) async {
    // Removed first, because a binding whose role or subjects drifted cannot be edited into the
    // right shape by a create, and the parts that drift are the parts that decide who holds
    // cluster-wide rights.
    await context.shell.run(
      Command('kubectl', <String>['delete', 'clusterrolebinding', name, '--ignore-not-found']),
    );
    final CommandResult created = await context.shell.run(Command('kubectl', _create.sublist(1)));
    if (!created.ok) {
      throw CommandFailed(argv: _create, exitCode: created.exitCode, stderr: created.stderr);
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    await context.shell.run(
      Command('kubectl', <String>['delete', 'clusterrolebinding', name, '--ignore-not-found']),
    );
  }

  List<String> get _create => <String>[
    'kubectl',
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
