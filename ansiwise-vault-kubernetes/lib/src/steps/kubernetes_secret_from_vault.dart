import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';

/// Materializes an entry of Vault into a Secret on a cluster.
///
/// **This step knows TWO tools, and that is what this package is for.** It reads values out of Vault
/// and writes them onto a cluster; as two rows it could not exist, because a step that measured
/// something has no way to tell a later step what it found — the facts a run carries are booleans,
/// an answer comes from the operator, and an argument is fixed when the program is resolved. The
/// only other shape would be a row that says "for each of these, composed this way", and that is a
/// language rather than a mechanism. So it is one step, and it stands in a package whose subject is
/// the PAIR rather than inside either tool package: a vendor driving Vault and no cluster resolves
/// no cluster client because of it, and a vendor driving a cluster and keeping no Vault resolves no
/// secret store.
///
/// **Why this exists rather than a step that mints where the value is needed.** Two components
/// regularly need one credential: a blueprint creates a client with a secret, and the application
/// authenticates with the same secret. A step that minted into the first place could not supply the
/// second without reading back what it wrote, and reading a credential in order to hand it on is how
/// it reaches somewhere it was not meant to be. So nothing mints here at all. The value comes into
/// being ONCE, in the store, and this is called once per consuming workload.
///
/// **It is the same act the cluster's own secret operator performs later.** Every workload reads its
/// credentials out of the store through that operator; what makes these entries different is only
/// that they are needed before the operator exists. So the paths are the same paths, and nothing is
/// minted twice or held in two places.
///
/// **Applied and not created.** The store holds the truth. If an entry gains a field, this puts it
/// on the cluster; if the Secret was deleted by hand, this puts it back. What it never does is write
/// something the store does not say.
///
/// **The check compares the FIELDS and not the existence of the object.** A Secret that stands and
/// is missing a field the store gained, or carries a value the store has since rotated, is work this
/// step has to do — and a check that stopped at "an object of that name is there" reported it as
/// done. Measured on a live installation: the entry carried six fields, the Secret five, and five
/// consecutive runs called the row satisfied. What makes the comparison affordable is that this step
/// reads the entry anyway in order to write it, so the values are already in its hands; what keeps
/// it from spending them is that the wanted value is ENCODED to compare against the cluster's
/// answer rather than the cluster's answer being decoded, and only the KEY of a field that differs
/// is ever named.
///
/// **The values reach the cluster through a file and never through an argument.** An argument is
/// visible in a process listing to every process on the host. The file is readable by its owner
/// alone, stands in the directory the row names — a memory file system on the machines this is meant
/// for — and is removed whether the apply succeeded or not.
final class KubernetesSecretFromVault extends ReversibleStep<bool> {
  /// Writes the entry at [path] into the Secret [name] in [namespace].
  const KubernetesSecretFromVault({
    required this.repository,
    required this.mount,
    required this.path,
    required this.name,
    required this.namespace,
    this.labels = const <String>[],
    required this.fields,
    required this.staging,
    this.kubectl = const Kubectl(),
    required this.layout,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory KubernetesSecretFromVault.fromArguments(Arguments arguments) => KubernetesSecretFromVault(
    repository: arguments.text('repository'),
    mount: arguments.text('mount'),
    path: arguments.text('path'),
    name: arguments.text('name'),
    namespace: arguments.text('namespace'),
    labels: arguments.has('labels') ? arguments.textList('labels') : const <String>[],
    fields: arguments.textList('fields'),
    staging: arguments.text('staging'),
    kubectl: Kubectl.fromArguments(arguments),
    layout: VaultLayout.fromArguments(arguments),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          "the checkout this run reads from, which carries the profile and Vault's own credential "
          'file',
    ),
    ArgumentSpec(
      name: 'mount',
      kind: ArgumentKind.text,
      describes: 'the mount of the store the entry stands on',
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
      name: 'labels',
      kind: ArgumentKind.textList,
      required: false,
      defaultValue: <String>[],
      describes:
          'the labels the Secret carries, each as <key>=<value>. A Secret is data and needs none to '
          'be read BY NAME — what needs one is a reader that finds its secrets by SELECTOR and '
          'therefore never sees an unlabelled object at all. Naming the wrong one, or none, is a '
          'reference that stays unresolved and is sent onward as an empty value, which the far side '
          'reports as a credential that is wrong rather than as one that is missing',
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
    Kubectl.argument,
    ...VaultLayout.arguments,
    elevationArgument,
  ];

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

  /// The labels it carries, each as `<key>=<value>`.
  ///
  /// Empty for a Secret nothing selects on, which is most of them. What needs one is a reader that
  /// finds its secrets by SELECTOR rather than by name: to such a reader an unlabelled Secret does
  /// not exist, and the reference to it stays unresolved and travels onward as an empty value.
  final List<String> labels;

  /// Which field becomes which key, each written `key=field`.
  final List<String> fields;

  /// Where the manifest is written and removed again.
  final String staging;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// Where Vault's own facts stand, and under which names.
  ///
  /// The same profile and the same credential file every other step of the vault family reads, so it
  /// declares the same names. A step that took the layout from a row for the rest of the family and
  /// from a literal for this one would open a path the operator never configured, and only for the
  /// Secrets — the rest of the run would finish.
  final VaultLayout layout;

  /// `0600` — the file holds every value of the Secret in the clear for as long as the apply takes.
  static const int mode = 0x180;

  /// The mode the staging directory is made with, which is 0700.
  static const int stagingMode = 448;

  /// Where the manifest stands while the cluster client reads it.
  String pathFor() => '$staging/$namespace-$name.yaml';

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    final _Secret onCluster = await _held(context);
    if (onCluster.refusal case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final Map<String, String>? held = onCluster.values;
    if (held == null) {
      return const CheckResult.ready();
    }
    // READ ONLY ONCE THE OBJECT IS THERE. An absent Secret is work to do whatever the store holds,
    // so a dry run on a machine whose entry an earlier row has not written yet never reaches the
    // store at all.
    final _Entry entry = await _read(context);
    if (entry.refusal case final String refusal) {
      // Neither satisfied nor ready: with the entry unreadable there is nothing to compare the
      // standing Secret against, and a run that answered either would be answering about the store
      // without having read it.
      return CheckResult.blocked(refusal);
    }
    final List<String> differing = <String>[
      for (final MapEntry<String, String> field in entry.values.entries)
        if (held[field.key] != _asTheClusterKeepsIt(field.value)) field.key,
    ];
    if (differing.isEmpty) {
      // What was actually compared, and not a claim about the entry as a whole: a field the row
      // does not write is not looked at, so the Secret may hold more than this sentence covers.
      return CheckResult.satisfied('$name in $namespace carries every field this row writes');
    }
    // The KEYS and never the values, and all of them at once — an operator told about one field per
    // run is an operator running the whole thing once per field.
    context.log.info('$name in $namespace differs from this run in ${differing.join(', ')}');
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      // The command and the file it will read, and nothing of what the file will hold. A plan is
      // written into the record an operator keeps, so a plan carrying the values would put every
      // credential of this Secret into it.
      StepPlan.argv(kubectl.argv(<String>['apply', '--filename', pathFor()]));

  @override
  Future<void> apply(StepContext context) async {
    final _Entry entry = await _read(context);
    if (entry.refusal case final String refusal) {
      throw StateError(refusal);
    }
    final String file = pathFor();
    // THE DIRECTORY IS MADE HERE, EVERY RUN, RATHER THAN ASSUMED. A row points this at a place the
    // installation chose, and the obvious choice is one the machine wipes: a directory under /run
    // is a tmpfs that is empty again after every restart. Assumed, the step fails on writing the
    // file and what an operator reads is a path that "cannot be created", which says nothing about
    // whose job it was to create it.
    //
    // 448 is 0700, written as the number the machine stores. The file below is already 0600, and a
    // world-listable directory around it would still say which namespace holds which secret.
    await context.files.createDirectory(staging, mode: stagingMode, elevated: elevated);
    await context.files.write(file, manifestOf(entry.values), mode: mode, elevated: elevated);
    try {
      final Command apply = _readingWhatWasWritten.command(<String>['apply', '--filename', file]);
      final CommandResult applied = await context.shell.run(apply);
      if (!applied.ok) {
        throw CommandFailed(
          argv: apply.argv,
          exitCode: applied.exitCode,
          stdout: '',
          stderr: applied.stderr,
        );
      }
    } finally {
      // In a finally: a failed apply would otherwise leave every value of the Secret standing in
      // the clear on the machine.
      await context.files.delete(file, elevated: elevated);
    }
  }

  /// The client that READS the staged manifest, which is the same identity that wrote it.
  ///
  /// **Whoever wrote a file is who can read it back.** The manifest is written as root when the row
  /// says the staging directory belongs to root, into a directory made 0700 for the same reason —
  /// and a client invoked as the account the run started as is then handed a path it cannot stat.
  /// What that produces is a failure about a path rather than about an identity: "cannot be
  /// accessed: permission denied", from a step that had just written the file successfully.
  ///
  /// This is not the row's second decision. `kubectl_needs_root` says whether the CLIENT needs root
  /// to reach the cluster at all, which is a different question with a different answer; this is the
  /// step keeping one act consistent with itself, and a row that already answered root for the file
  /// should not have to answer it twice for the reading of that same file.
  Kubectl get _readingWhatWasWritten =>
      elevated && !kubectl.elevated ? Kubectl(kubectl.invocation, true) : kubectl;

  /// Whether [namespace] already holds a Secret called [name].
  ///
  /// Read before the apply, because the delete in the undo removes the Secret whether or not this
  /// run wrote it, and every pod that mounts it is then a pod that cannot start.
  ///
  /// Whether it is there, and never what it holds. What a capture returns is handed to the undo and
  /// is kept for as long as the run is, so a capture holding the values would carry every credential
  /// of this Secret through the whole run. The check reads the fields because it has to decide
  /// whether they are right; the undo only has to decide whether this run created the object, and
  /// that is one boolean.
  @override
  Future<bool> capture(StepContext context) => _isThere(context);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      kubectl.command(<String>[
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
      kubectl.observing(<String>['get', 'secret', name, '--namespace', namespace, '-o', 'name']),
    );
    if (found.ok) {
      return true;
    }
    // A GET OF A NAMED OBJECT EXITS ONE FOR TWO DIFFERENT CLUSTERS, and this is a capture: its
    // false half is what deletes the Secret, so a cluster that could not be asked read as one this
    // run created and the clean-up after some OTHER step failed took away a credential every
    // workload reading it depends on. A LIST of the kind answers empty at exit zero for a namespace
    // holding none, and exits non-zero only where the cluster itself did not answer.
    final CommandResult listed = await context.shell.run(
      kubectl.observing(<String>['get', 'secret', '--namespace', namespace, '-o', 'name']),
    );
    if (listed.ok) {
      return false;
    }
    context.log.warn(
      'whether $namespace already held a Secret called $name could not be read, so an undo will '
      'leave it alone rather than delete one this run may not have created: the cluster answered '
      '${listed.exitCode}'
      '${listed.stderr.trim().isEmpty ? '' : ' — ${listed.stderr.trim()}'}',
    );
    return true;
  }

  /// What the Secret holds, keyed as the cluster keeps it — or that there is none, or why it cannot
  /// be read.
  ///
  /// Three answers and not two, for the reason the client's own elevation argument is there: a
  /// client that cannot reach the cluster can write its refusal on its output and still exit ZERO,
  /// and a step that read that as "the object holds nothing" would rewrite a Secret on every run
  /// while reporting the run finished.
  Future<_Secret> _held(StepContext context) async {
    final CommandResult read = await context.shell.run(
      kubectl.observing(<String>['get', 'secret', name, '--namespace', namespace, '-o', 'json']),
    );
    if (!read.ok) {
      return const _Secret.absent();
    }
    final Map<String, Object?>? object = decodedObject(read.stdout);
    if (object == null) {
      return _Secret.unreadable(
        'reading $name in $namespace succeeded and answered with something that is not an object, '
        'so what the Secret holds is unknown — a client that cannot reach the cluster writes its '
        'refusal on its output and exits zero',
      );
    }
    final Object? data = object['data'];
    // A Secret carrying no data at all is an object that holds none of the fields this row writes,
    // which is work to do rather than something that cannot be read.
    return _Secret.holding(<String, String>{
      if (data is Map<String, Object?>)
        for (final MapEntry<String, Object?> field in data.entries)
          if (field.value case final String kept) field.key: kept,
    });
  }

  /// [value] written the way the cluster keeps it, so a comparison never decodes a credential out of
  /// the cluster's answer.
  ///
  /// The manifest is written with `stringData`, and the API server stores what it is given under
  /// `data`, base64 of the same bytes — so encoding what this run would write is the same comparison
  /// as decoding what the cluster answered, with one fewer place a credential is turned back into
  /// text.
  static String _asTheClusterKeepsIt(String value) => base64Encode(utf8.encode(value));

  /// The Secret as the cluster client reads it.
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
    if (labels.isNotEmpty) '  labels:',
    for (final String label in labels)
      '    ${label.substring(0, label.indexOf('='))}: '
          '"${label.substring(label.indexOf('=') + 1)}"',
    'type: Opaque',
    'stringData:',
    // Quoted, because a value that is all digits reads as a number and the API server then refuses
    // the object for a type nobody gave it.
    for (final MapEntry<String, String> value in values.entries) '  ${value.key}: "${value.value}"',
    '',
  ].join('\n');

  /// The fields this Secret carries, read out of the store.
  Future<_Entry> _read(StepContext context) async {
    final VaultProfile store = await vaultProfileFrom(context, repository, layout: layout);
    if (store.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }
    final ArgumentText entry = store.forThisInstallation(context, path);
    if (entry.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }
    final RootToken token = await rootTokenFrom(
      context,
      vaultCredentialsPath(context, repository, layout: layout),
    );
    if (token.refusal case final String refusal) {
      return _Entry.unreadable(refusal);
    }

    final String dataPath = '$mount/data/${entry.value ?? ''}';
    final HttpAnswer answer = await context.http.send(
      vaultRead(store.url ?? '', dataPath, token: token.value ?? ''),
    );
    if (isAbsent(answer)) {
      return _Entry.unreadable(
        '$dataPath is not in the store, and it is where this Secret is read '
        'from',
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

/// What the Secret on the cluster carries, or that there is none, or why it cannot be read.
final class _Secret {
  /// Records that no Secret of that name stands in that namespace.
  const _Secret.absent() : values = null, refusal = null;

  /// Records that it stands and holds [values], each exactly as the cluster keeps it.
  const _Secret.holding(Map<String, String> this.values) : refusal = null;

  /// Records that it could not be read, because [refusal].
  const _Secret.unreadable(String this.refusal) : values = null;

  /// What it holds, or null where there is no such Secret or none could be read.
  final Map<String, String>? values;

  /// Why nothing can be read, or null when it can.
  final String? refusal;
}

/// What one Secret would carry, or why it cannot be read.
final class _Entry {
  const _Entry.values(this.values) : refusal = null;

  const _Entry.unreadable(this.refusal) : values = const <String, String>{};

  final Map<String, String> values;

  final String? refusal;
}
