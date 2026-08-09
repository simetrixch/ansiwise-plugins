import 'package:ansiwise_api/ansiwise_api.dart';

import 'argument_text.dart';
import 'cluster_profile.dart';
import 'vault_api.dart';

/// Materializes an entry of the secret store into a Secret on this cluster.
///
/// **Why this exists rather than a step that mints where the value is needed.** Two components
/// regularly need one credential: the identity provider's blueprint creates an OIDC client with a
/// secret, and the application authenticates with the same secret. A step that minted into the first
/// place could not supply the second without reading back what it wrote, and reading a credential in
/// order to hand it on is how it reaches somewhere it was not meant to be. So nothing mints here at
/// all. The value comes into being ONCE, in the store, and this is called once per consumer.
///
/// **It is the same act the secret operator performs after the handoff.** Every application of this
/// platform reads its credentials out of the store through that operator; what makes these entries
/// different is only that they are needed before the operator exists. So the paths are the same
/// paths, and nothing is minted twice or held in two places.
///
/// **Applied and not created.** The store holds the truth. If an entry gains a field, this puts it
/// on the cluster; if the Secret was deleted by hand, this puts it back. What it never does is write
/// something the store does not say.
///
/// **The values reach the cluster through a file and never through an argument.** An argument is
/// visible in a process listing to every process on the host — the objection that moved this
/// platform's own work off `kubectl exec`. The file is readable by its owner alone, stands under a
/// directory that is a memory file system on the machines this runs on, and is removed whether the
/// apply succeeded or not.
final class KubernetesSecretFromVault extends ReversibleStep<bool> {
  /// Writes the entry at [path] into the Secret [name] in [namespace].
  const KubernetesSecretFromVault({
    required this.repository,
    required this.mount,
    required this.path,
    required this.name,
    required this.namespace,
    required this.fields,
    required this.staging,
  });

  /// Builds the step from what the program gave it.
  factory KubernetesSecretFromVault.fromArguments(Arguments arguments) => KubernetesSecretFromVault(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    name: arguments.text('name'),
    namespace: arguments.text('namespace'),
    fields: arguments.textList('fields'),
    staging: arguments.text('staging'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this installation runs from, which carries the cluster's own profile and "
          'the credentials of the secret store',
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes: 'the mount of the secret store the entry stands on',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the entry, with the marked slots this run fills',
    ),
    ArgumentSpec(
      name: 'name',
      kind: ArgumentKind.text,
      describes: 'the Secret this writes on the cluster',
    ),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace it is written in',
    ),
    ArgumentSpec(
      name: 'fields',
      kind: ArgumentKind.textList,
      describes:
          'which fields of the entry become which keys of the Secret, written key=field — the two '
          'names differ because each side was named by whoever reads it',
    ),
    ArgumentSpec(
      name: 'staging',
      kind: ArgumentKind.text,
      describes: 'the directory the manifest is written in and removed from again',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>[vaultStageAnswer];

  /// The checkout.
  final String repository;

  /// The mount.
  final String mount;

  /// The entry, before its marked slots are filled.
  final String path;

  /// The Secret.
  final String name;

  /// Where it goes.
  final String namespace;

  /// Which field becomes which key, each written `key=field`.
  final List<String> fields;

  /// Where the manifest is written and removed again.
  final String staging;

  /// `0600` — the file holds every value of the Secret in the clear for as long as the apply takes.
  static const int mode = 0x180;

  /// Where the manifest stands while `kubectl` reads it.
  String pathFor() => '$staging/$namespace-$name.yaml';

  @override
  Future<CheckResult> check(StepContext context) async {
    // Whether the Secret is there, and never what it holds. Comparing would mean reading a
    // credential off the cluster to decide whether to write it again, and the store is the truth
    // either way — a Secret that disagrees with it is put right by applying, not by measuring.
    return await _isThere(context)
        ? CheckResult.satisfied('$name is in $namespace, carrying what $path holds')
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['kubectl', 'apply', '--filename', pathFor()]);

  @override
  Future<void> apply(StepContext context) async {
    final _Entry entry = await _read(context);
    if (entry.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String file = pathFor();
    await context.files.write(file, manifestOf(entry.values), mode: mode);
    try {
      final List<String> argv = <String>['kubectl', 'apply', '--filename', file];
      final CommandResult applied = await context.shell.run(Command('kubectl', argv.sublist(1)));
      if (!applied.ok) {
        throw CommandFailed(argv: argv, exitCode: applied.exitCode, stderr: applied.stderr);
      }
    } finally {
      // In a finally: a failed apply would otherwise leave every value of the Secret standing in
      // the clear on the machine.
      await context.files.delete(file);
    }
  }

  /// Whether [namespace] already holds a Secret called [name].
  ///
  /// Read before the apply, because the delete in the undo removes the Secret whether or not this
  /// run wrote it, and every pod that mounts it is then a pod that cannot start.
  ///
  /// Whether it is there, and never what it holds — the same reading the check makes, for the same
  /// reason: taking the values off the cluster would carry a credential through this run and into
  /// the record. So nothing captured here is secret material, and a Secret that was already there
  /// stands, carrying what the store says.
  @override
  Future<bool> capture(StepContext context) => _isThere(context);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      Command('kubectl', <String>[
        'delete',
        'secret',
        name,
        '--namespace',
        namespace,
        '--ignore-not-found',
      ]),
    );
  }

  /// Whether the Secret this step writes stands in its namespace.
  Future<bool> _isThere(StepContext context) async {
    final CommandResult found = await context.shell.run(
      Command.observing('kubectl', <String>[
        'get',
        'secret',
        name,
        '--namespace',
        namespace,
        '-o',
        'name',
      ]),
    );
    return found.ok;
  }

  /// The Secret as `kubectl` reads it.
  ///
  /// `stringData` and not `data`, so nothing here encodes anything: the API server takes the values
  /// as they are. An encoding step of our own would be one more place a value is truncated without
  /// anyone noticing.
  String manifestOf(Map<String, String> values) => <String>[
    'apiVersion: v1',
    'kind: Secret',
    'metadata:',
    '  name: $name',
    '  namespace: $namespace',
    'type: Opaque',
    'stringData:',
    // Quoted, because a value that is all digits reads as a number and the API server then refuses
    // the object for a type nobody gave it.
    for (final MapEntry<String, String> value in values.entries) '  ${value.key}: "${value.value}"',
    '',
  ].join('\n');

  /// The fields this Secret carries, read out of the store.
  Future<_Entry> _read(StepContext context) async {
    final ClusterProfile store = await clusterProfileFrom(context, repository);
    if (store.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }
    final ArgumentText entry = store.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }
    final RootToken token = await rootTokenFrom(context, vaultCredentialsPath(context, repository));
    if (token.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }

    final String dataPath = '$mount/data/${entry.value ?? ''}';
    final HttpAnswer answer = await context.http.send(
      vaultRead(store.url ?? '', dataPath, token: token.value ?? ''),
    );
    if (isAbsent(answer)) {
      return _Entry.unreadable(
        '$dataPath is not in the secret store, and it is where this Secret is read from',
      );
    }
    final Object? held = decodedData(answer.body)?['data'];
    if (held is! Map<String, Object?>) {
      return _Entry.unreadable('$dataPath answered with something that is not an entry');
    }

    final Map<String, String> values = <String, String>{};
    final List<String> missing = <String>[];
    for (final String declared in fields) {
      final int equals = declared.indexOf('=');
      if (equals <= 0) {
        missing.add('"$declared" is not a <key>=<field> pair');
        continue;
      }
      final String key = declared.substring(0, equals).trim();
      final String field = declared.substring(equals + 1).trim();
      final Object? value = held[field];
      if (value is! String || value.isEmpty) {
        // Named, never valued. What is missing is what an operator needs to know; what it should
        // have held is the credential.
        missing.add('$dataPath carries no $field');
        continue;
      }
      values[key] = value;
    }
    // Everything missing at once, because an operator told about one field per run is an operator
    // running the whole thing once per field.
    return missing.isEmpty ? _Entry.values(values) : _Entry.unreadable(missing.join('; '));
  }
}

/// What one Secret would carry, or why it cannot be read.
final class _Entry {
  const _Entry.values(this.values) : refusal = null;

  const _Entry.unreadable(this.refusal) : values = const <String, String>{};

  final Map<String, String> values;

  final String? refusal;
}
