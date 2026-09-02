import 'dart:convert';

import 'package:ansiwise_core/ansiwise_core.dart';

import 'kubectl.dart';

/// Marks one of the cluster's storage classes as the one a claim gets when it names none.
///
/// Almost every claim this platform makes names no class, so without a default they are all accepted
/// and none of them is ever satisfied — a workload that waits for ever with nothing saying why.
///
/// **The class is found and never configured, and finding it means finding exactly ONE.** Which
/// class the volume addon produced is the addon's business; naming it in a program file would be a
/// second answer that only agrees with the first by accident. Where the cluster carries SEVERAL and
/// none of them is the default, this refuses and names them: which of several should catch every
/// claim that names none is a decision, and taking whichever the cluster listed first would make it
/// silently — the order is the API server's and can differ between two readings of the same cluster,
/// so the same program would produce different clusters and nothing would say why.
///
/// **This waits for the class rather than reporting that there was none.** The addon produces it
/// shortly after it is switched on, so a step that looked once and moved on would leave a first
/// install with no default at all — correct only if somebody comes back and runs the program a
/// second time, which nothing arranges.
final class SetDefaultStorageClass extends ReversibleStep<DefaultStorageClassBefore> {
  /// Waits up to [timeoutSeconds] for a class and marks the first one as the default.
  const SetDefaultStorageClass({
    required this.timeoutSeconds,
    required this.intervalSeconds,
    this.kubectl = const Kubectl(),
  });

  /// Builds the step from what the program gave it.
  factory SetDefaultStorageClass.fromArguments(Arguments arguments) => SetDefaultStorageClass(
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
    kubectl: Kubectl.fromArguments(arguments),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'timeout_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long the volume addon is given to produce a storage class',
      required: false,
      defaultValue: 120,
    ),
    ArgumentSpec(
      name: 'interval_seconds',
      kind: ArgumentKind.integer,
      describes: 'how long to leave between looks for one',
      required: false,
      defaultValue: 5,
    ),
    Kubectl.argument,
    Kubectl.elevationArgument,
  ];

  /// The mark that says a class is the default.
  static const String annotation = 'storageclass.kubernetes.io/is-default-class';

  /// How long the addon is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

  /// How the cluster is reached.
  final Kubectl kubectl;

  @override
  Future<CheckResult> check(StepContext context) async {
    final Map<String, bool>? classes = await _classes(context);
    if (classes == null) {
      return const CheckResult.blocked(
        'the storage classes could not be read, so nothing says whether there is a default',
      );
    }
    final String? already = _default(classes);
    if (already != null) {
      return CheckResult.satisfied('$already is the default storage class');
    }
    if (classes.length > 1) {
      return CheckResult.blocked(_undecided(classes));
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    'would wait up to ${timeoutSeconds}s for a storage class and mark it as the default — and '
    'refuse a cluster that carries several with no default among them',
  );

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    while (true) {
      final Map<String, bool> classes = await _classes(context) ?? const <String, bool>{};
      if (_default(classes) != null) {
        return;
      }
      if (classes.length > 1) {
        throw StateError(_undecided(classes));
      }
      if (classes.isNotEmpty) {
        await _mark(context, classes.keys.single, true);
        return;
      }
      if (!context.clock.now().isBefore(giveUp)) {
        throw WaitedTooLong(
          waitingFor: 'the volume addon to produce a storage class to mark as the default',
          deadline: Duration(seconds: timeoutSeconds),
        );
      }
      await context.clock.sleep(Duration(seconds: intervalSeconds));
    }
  }

  /// Which class carried the mark before this ran, that none did, or that neither could be read.
  ///
  /// Which class this step will mark cannot be read yet — the apply waits for the volume addon to
  /// produce one — so what is kept is whether the cluster had a default at all. A cluster that
  /// arrived with one keeps it, and a mark read at undo time cannot say who put it there.
  @override
  Future<DefaultStorageClassBefore> capture(StepContext context) async {
    final Map<String, bool>? classes = await _classes(context);
    if (classes == null) {
      context.log.warn(
        'the storage classes could not be read, so an undo will leave the default mark alone '
        'rather than take it off a class this run may not have marked',
      );
      return const DefaultStorageClassBefore.unmeasured();
    }
    if (_default(classes) case final String marked) {
      return DefaultStorageClassBefore.of(marked);
    }
    return const DefaultStorageClassBefore.none();
  }

  @override
  Future<void> undo(StepContext context, DefaultStorageClassBefore captured) async {
    if (captured.unmeasured || captured.marked != null) {
      return;
    }
    final Map<String, bool> classes = await _classes(context) ?? const <String, bool>{};
    final String? marked = _default(classes);
    if (marked == null) {
      return;
    }
    await _mark(context, marked, false);
  }

  /// Every storage class and whether it carries the mark, or null when they cannot be read.
  Future<Map<String, bool>?> _classes(StepContext context) async {
    final CommandResult classes = await context.shell.run(
      kubectl.observing(<String>[
        'get',
        'storageclass',
        '-o',
        r'jsonpath={range .items[*]}{.metadata.name}{" "}'
            '{.metadata.annotations.$_escapedAnnotation}'
            r'{"\n"}{end}',
      ]),
    );
    if (!classes.ok) {
      return null;
    }
    final Map<String, bool> found = <String, bool>{};
    for (final String line in classes.stdout.split('\n')) {
      final List<String> fields = line.trimRight().split(' ');
      if (fields.isEmpty || fields.first.trim().isEmpty) {
        continue;
      }
      found[fields.first.trim()] = fields.length > 1 && fields[1].trim() == 'true';
    }
    return found;
  }

  /// Why this cluster's classes leave nothing to mark, for the check and for the apply alike.
  ///
  /// One sentence in both places rather than two that could come to say different things about the
  /// same cluster: the check is what a dry run prints, and the apply is what a real run stops on
  /// when a class appeared between the two.
  static String _undecided(Map<String, bool> classes) =>
      'this cluster carries ${classes.length} storage classes and none of them is the default: '
      '${classes.keys.join(', ')}. Which of them catches every claim that names none is a decision, '
      'and nothing here makes it — mark one on the cluster, or leave the cluster with one class';

  String? _default(Map<String, bool> classes) {
    for (final MapEntry<String, bool> storageClass in classes.entries) {
      if (storageClass.value) {
        return storageClass.key;
      }
    }
    return null;
  }

  Future<void> _mark(StepContext context, String storageClass, bool isDefault) async {
    final Command mark = kubectl.command(<String>[
      'patch',
      'storageclass',
      storageClass,
      '--type',
      'merge',
      '-p',
      jsonEncode(<String, Object>{
        'metadata': <String, Object>{
          'annotations': <String, String>{annotation: '$isDefault'},
        },
      }),
    ]);
    final CommandResult marked = await context.shell.run(mark);
    if (!marked.ok) {
      throw CommandFailed(
        argv: mark.argv,
        exitCode: marked.exitCode,
        stdout: '',
        stderr: marked.stderr,
      );
    }
  }

  /// The mark's name with the dots escaped, because a reading path splits on them.
  static final String _escapedAnnotation = annotation.replaceAll('.', r'\.');
}

/// Which storage class carried the default mark before a run marked one, as far as it could be read.
///
/// **Three states, because the undo acts on exactly one of them.** A cluster that arrived WITH a
/// default keeps it, whichever class it is; a cluster that arrived without one has the mark this
/// run made taken off again. The third is neither, and it is the one easiest to lose: a cluster
/// whose classes could not be read, taken as the same empty map a cluster with no default gives,
/// has the undo take the mark off a class this run may never have marked, while cleaning up after
/// some other step failed.
final class DefaultStorageClassBefore {
  /// Records that no class of this cluster carried the mark, so this run made the one that does.
  const DefaultStorageClassBefore.none() : marked = null, unmeasured = false;

  /// Records the class that already carried the mark.
  const DefaultStorageClassBefore.of(String this.marked) : unmeasured = false;

  /// Records that the classes could not be read, so an undo has nothing it may act on.
  const DefaultStorageClassBefore.unmeasured() : marked = null, unmeasured = true;

  /// The class that carried the mark, or null where none did or nothing could be read.
  final String? marked;

  /// Whether the classes could not be read, which is not the same as a cluster with no default.
  final bool unmeasured;
}
