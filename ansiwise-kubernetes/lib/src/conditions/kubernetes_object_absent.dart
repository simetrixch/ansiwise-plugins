import 'package:ansiwise_core/ansiwise_core.dart';

import '../steps/kubectl.dart';

/// Whether one named object is absent from the cluster.
///
/// ONE condition, pointed at one object by the installation that uses it, and registered under
/// whatever name that installation chose. It is what lets a row install a thing only where none
/// stands, so a rerun leaves alone what something else on the cluster already holds.
///
/// **ONLY THE CLUSTER'S OWN "NONE" HOLDS.** A get of the named object with `--ignore-not-found`
/// exits zero and writes nothing where the cluster holds no such object, and writes the object's
/// name where it does. Every other exit is a cluster that was not asked: no API server yet, a
/// refused credential, a network that is not there. Reading that as "none stands" would install
/// over an object nobody looked at, so it is [ConditionUnanswerable] and the run stops.
///
/// **A KIND THE CLUSTER DOES NOT SERVE IS ABSENT TOO**, because no object of it can stand. On a new
/// cluster every condition is measured before the first row runs, which is before the release that
/// brings the kind's definition. kubectl tells this apart from an unreachable cluster only in its
/// words — the exit code is the same — so the sentence is read here. Should kubectl ever reword
/// it, the reading falls to the unanswerable side and stops the run; it never turns into "absent".
final class KubernetesObjectAbsent implements Predicate {
  /// Asks whether [kind]/[name], in [namespace] where it has one, is absent.
  const KubernetesObjectAbsent({
    required this.kind,
    required this.name,
    this.namespace,
    this.kubectl = const Kubectl(),
  });

  /// Builds the condition from what one installation told it.
  factory KubernetesObjectAbsent.fromArguments(Arguments values) => KubernetesObjectAbsent(
    kind: values.text('kind'),
    name: values.text('name'),
    namespace: values.optionalText('namespace'),
    kubectl: Kubectl.fromArguments(values),
  );

  /// What this condition has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'kind',
      kind: ArgumentKind.text,
      describes: 'the kind of the object, as kubectl get takes it',
    ),
    ArgumentSpec(name: 'name', kind: ArgumentKind.text, describes: 'the name of the object'),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the namespace the object stands in; left out for a cluster-scoped kind',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// What kubectl writes for a kind the API server does not serve.
  static const String _unservedKind = "the server doesn't have a resource type";

  /// The kind of the object.
  final String kind;

  /// The name of the object.
  final String name;

  /// The namespace the object stands in, or null for a cluster-scoped kind.
  final String? namespace;

  /// How kubectl is invoked.
  final Kubectl kubectl;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    final List<String> asking = <String>[
      if (namespace case final String each) ...<String>['-n', each],
      'get',
      kind,
      name,
      '--ignore-not-found',
      '-o',
      'name',
    ];
    final CommandResult asked = await context.shell.run(kubectl.observing(asking));
    final String object = '$kind "$name"${namespace == null ? '' : ' in $namespace'}';
    if (asked.ok) {
      final String answer = asked.trimmed;
      if (answer.isEmpty) {
        return PredicateResult.holds('the cluster holds no $object');
      }
      if (answer.endsWith('/$name')) {
        return PredicateResult.doesNotHold('$object stands');
      }
    } else if (asked.stderr.contains(_unservedKind)) {
      return PredicateResult.holds('the cluster serves no kind $kind, so no $object stands');
    }
    throw ConditionUnanswerable(
      'the cluster would not say whether $object stands, so nothing here knows whether it does: '
      '${kubectl.argv(asking).join(' ')} answered ${asked.exitCode}'
      '${asked.ok ? ' with "${asked.trimmed}"' : ''}'
      '${asked.stderr.trim().isEmpty ? '' : ' — ${asked.stderr.trim()}'}\n'
      'reading that as "none stands" would install over an object nobody looked at',
    );
  }
}
