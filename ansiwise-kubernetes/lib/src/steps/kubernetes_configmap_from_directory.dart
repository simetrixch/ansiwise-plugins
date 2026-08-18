import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Makes a ConfigMap out of a directory of the checkout, one key per file.
///
/// **What it is for.** Some releases mount a ConfigMap at a path in their pod and discover whatever
/// files they find there on startup — declarations, fragments, rules. Those files are not
/// Kubernetes objects and are not applied: what has to exist before the release is the ConfigMap,
/// and nothing built it.
///
/// **A directory and not a list of files.** A file added to the directory reaches the cluster
/// without anything else being edited — no program row, no argument, no second list to keep in step
/// with the first. A list here would be a second description of the directory, and the two would
/// disagree the first time somebody added a file and forgot.
///
/// **Replaced and not merged, which is the point rather than a shortcut.** A key that stays behind
/// after its file was deleted is a declaration this cluster still carries and nobody meant to keep.
/// `kubectl create --dry-run=client` composes the object from the directory as it is now, and the
/// apply makes the cluster hold exactly that.
///
/// **No credential travels here.** What this composes is the files as they stand in the checkout,
/// so what belongs in the directory is declarations that reference their secrets by name — the pod
/// resolves those from its own environment — and never the values themselves.
final class KubernetesConfigmapFromDirectory extends ReversibleStep<bool> {
  /// Makes the ConfigMap [name] in [namespace] out of [directory] under [repository].
  const KubernetesConfigmapFromDirectory({
    required this.repository,
    required this.directory,
    required this.name,
    required this.namespace,
    required this.staging,
    this.kubectl = const Kubectl(),
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory KubernetesConfigmapFromDirectory.fromArguments(Arguments arguments) =>
      KubernetesConfigmapFromDirectory(
        repository: arguments.text('repository'),
        directory: arguments.text('directory'),
        name: arguments.text('name'),
        namespace: arguments.text('namespace'),
        staging: arguments.text('staging'),
        kubectl: Kubectl.fromArguments(arguments),
        elevated: arguments.has('elevated') && arguments.flag('elevated'),
      );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout the directory is read from',
    ),
    ArgumentSpec(
      name: 'directory',
      kind: ArgumentKind.text,
      describes: 'the directory, as a path under that checkout — every file in it becomes a key',
    ),
    ArgumentSpec(name: 'name', kind: ArgumentKind.text, describes: 'the ConfigMap this writes'),
    ArgumentSpec(
      name: 'namespace',
      kind: ArgumentKind.text,
      describes: 'the namespace it is written in',
    ),
    ArgumentSpec(
      name: 'staging',
      kind: ArgumentKind.text,
      describes: 'the directory the composed object is written in and removed from again',
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
    elevationArgument,
  ];

  /// The checkout.
  final String repository;

  /// The directory, relative to it.
  final String directory;

  /// The ConfigMap.
  final String name;

  /// Where it goes.
  final String namespace;

  /// Where the composed object stands while `kubectl` reads it.
  final String staging;

  /// How the cluster is reached.
  final Kubectl kubectl;

  /// `0644` — what this carries is declarations and no credential, so it is readable like the files
  /// it was composed from.
  static const int mode = 0x1a4;

  /// The mode the staging directory is made with, which is 0700.
  static const int stagingMode = 448;

  /// The client that READS the staged file, which is the same identity that wrote it.
  ///
  /// **Whoever wrote a file is who can read it back.** The file is written as root when the row says
  /// the staging directory belongs to root, and a client invoked as the account the run started as
  /// is then handed a path it cannot stat. What that produces is a failure about a path rather than
  /// about an identity, from a step that had just written the file successfully.
  ///
  /// `kubectl_needs_root` is a different question — whether the CLIENT needs root to reach the
  /// cluster at all — and a row that already answered root for the file should not answer it twice
  /// for the reading of that same file.
  Kubectl get _readingWhatWasWritten =>
      elevated && !kubectl.elevated ? Kubectl(kubectl.invocation, true) : kubectl;

  /// The directory as the machine holds it.
  String get path => '$repository/$directory';

  /// Where the composed object stands.
  String pathFor() => '$staging/$namespace-$name.yaml';

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(path, elevated: elevated)) {
      return CheckResult.blocked('$directory is not in this checkout, so there is nothing to make');
    }
    if ((await context.files.list(path, elevated: elevated)).isEmpty) {
      // An empty directory would compose a ConfigMap with no keys, and the pod would mount it and
      // discover nothing — which looks exactly like a release that came up correctly.
      return CheckResult.blocked('$directory holds no file, so the ConfigMap would carry no key');
    }
    // NO FILE IS INVOLVED, AND THAT IS THE CORRECTION. This used to ask `diff --filename` about the
    // staged file — which is composed inside apply and removed again in its own finally, so at check
    // time it never exists. The step could not answer its own postcondition on any machine: every
    // run reported "the cluster could not be asked", naming a path that was never meant to outlive
    // the apply that made it.
    //
    // Both sides are read instead, as JSON, and only the DATA is compared. The object the cluster
    // holds carries a resource version, a creation time and a managed-fields record that change on
    // their own, so comparing the whole object would report a difference on every run.
    final CommandResult wanted = await context.shell.run(
      _readingWhatWasWritten.observing(<String>[..._compose, '-o', 'json']),
    );
    if (!wanted.ok) {
      return CheckResult.blocked(
        'the object could not be composed from $directory: ${wanted.stderr.trim()}',
      );
    }
    final CommandResult held = await context.shell.run(
      _readingWhatWasWritten.observing(<String>[
        'get',
        'configmap',
        name,
        '--namespace',
        namespace,
        '-o',
        'json',
        '--ignore-not-found',
      ]),
    );
    if (!held.ok) {
      return CheckResult.blocked('the cluster could not be asked about $name: ${held.stderr}');
    }
    if (held.trimmed.isEmpty) {
      return const CheckResult.ready();
    }
    // A key that stays behind after its file was deleted is a declaration this cluster still carries
    // and nobody meant to keep, so the two maps are compared whole rather than key by key.
    if (_dataOf(wanted.trimmed) != _dataOf(held.trimmed)) {
      return const CheckResult.ready();
    }
    return CheckResult.satisfied('$name in $namespace carries what $directory holds');
  }

  /// The `data` of a ConfigMap written as JSON, rendered so two of them compare as text.
  ///
  /// Null where the text is not an object at all, which is a different answer from an object with no
  /// data: the first says the reading failed and the second says the map is empty.
  static String? _dataOf(String json) {
    final Object? decoded = _decoded(json);
    if (decoded is! Map<String, Object?>) {
      return null;
    }
    final Object? data = decoded['data'];
    if (data is! Map<String, Object?>) {
      return '{}';
    }
    final List<String> keys = data.keys.toList()..sort();
    return jsonEncode(<String, Object?>{for (final String key in keys) key: data[key]});
  }

  static Object? _decoded(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(kubectl.argv(<String>['apply', '--filename', pathFor()]));

  @override
  Future<void> apply(StepContext context) async {
    final Command compose = kubectl.command(<String>[..._compose, '-o', 'yaml']);
    final CommandResult composed = await context.shell.run(compose);
    if (!composed.ok) {
      throw CommandFailed(
        argv: compose.argv,
        exitCode: composed.exitCode,
        stdout: '',
        stderr: composed.stderr,
      );
    }
    final String file = pathFor();
    // Made here, every run: the obvious place to stage in is one the machine wipes, and a directory
    // under a memory filesystem is empty again after every restart. Assumed, the step fails on the
    // write with a message about a path that says nothing about whose job the path was.
    await context.files.createDirectory(staging, mode: stagingMode, elevated: elevated);
    await context.files.write(file, composed.stdout, mode: mode, elevated: elevated);
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
      await context.files.delete(file, elevated: elevated);
    }
  }

  /// Whether [namespace] already holds a ConfigMap called [name].
  ///
  /// Read before the apply, because the delete in the undo removes the object whether or not this
  /// run made it — and what a release mounts is that object, so removing one that was there before
  /// takes the configuration of an installation this run did not build with it.
  ///
  /// What the ConfigMap held before is not captured. The cluster answers with the object as it
  /// stands, resourceVersion and all, and applying that again is refused as a conflict once anything
  /// has changed the object since — which the apply of this step does. So a ConfigMap that was
  /// already there keeps the keys this run composed out of [directory].
  @override
  Future<bool> capture(StepContext context) async {
    final CommandResult found = await context.shell.run(
      kubectl.observing(<String>['get', 'configmap', name, '--namespace', namespace, '-o', 'name']),
    );
    return found.ok;
  }

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      kubectl.command(<String>[
        'delete',
        'configmap',
        name,
        '--namespace',
        namespace,
        '--ignore-not-found',
      ]),
    );
  }

  /// Composing the object from the directory, without sending anything.
  ///
  /// `--dry-run=client` is what makes this a composition rather than a create: `kubectl create` on
  /// its own refuses a ConfigMap that already exists, so a second run would fail on the very thing
  /// a second run is supposed to find already done.
  /// How the object is composed from the directory as it stands, without an output format.
  ///
  /// The format is added by the caller: the apply wants yaml to write, and the check wants json to
  /// compare. One list with a format baked in would have meant two lists that can drift apart.
  List<String> get _compose => <String>[
    'create',
    'configmap',
    name,
    '--namespace',
    namespace,
    '--from-file',
    path,
    '--dry-run=client',
  ];
}
