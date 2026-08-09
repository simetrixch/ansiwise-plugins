import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';

/// Marks one of the cluster's storage classes as the one a claim gets when it names none.
///
/// Almost every claim this platform makes names no class, so without a default they are all accepted
/// and none of them is ever satisfied — a workload that waits for ever with nothing saying why.
///
/// **The class is found and never configured.** Which one the volume addon produced is the addon's
/// business; naming it in a program file would be a second answer that only agrees with the first by
/// accident.
///
/// **This waits for the class rather than reporting that there was none.** The addon produces it
/// shortly after it is switched on, so a step that looked once and moved on would leave a first
/// install with no default at all — correct only if somebody comes back and runs the program a
/// second time, which nothing arranges. Waiting is the deliberate departure from what this replaces.
final class SetDefaultStorageClass extends ReversibleStep<String?> {
  /// Waits up to [timeoutSeconds] for a class and marks the first one as the default.
  const SetDefaultStorageClass({required this.timeoutSeconds, required this.intervalSeconds});

  /// Builds the step from what the program gave it.
  factory SetDefaultStorageClass.fromArguments(Arguments arguments) => SetDefaultStorageClass(
    timeoutSeconds: arguments.integer('timeout_seconds'),
    intervalSeconds: arguments.integer('interval_seconds'),
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
  ];

  /// The mark that says a class is the default.
  static const String annotation = 'storageclass.kubernetes.io/is-default-class';

  /// How long the addon is given.
  final int timeoutSeconds;

  /// How long to leave between looks.
  final int intervalSeconds;

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
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.nothing(
    'would wait up to ${timeoutSeconds}s for a storage class and mark the first one as the default',
  );

  @override
  Future<void> apply(StepContext context) async {
    final DateTime giveUp = context.clock.now().add(Duration(seconds: timeoutSeconds));
    while (true) {
      final Map<String, bool> classes = await _classes(context) ?? const <String, bool>{};
      if (_default(classes) != null) {
        return;
      }
      if (classes.isNotEmpty) {
        await _mark(context, classes.keys.first, true);
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

  /// The class that carries the mark already, or null when no class is the default.
  ///
  /// Which class this step will mark cannot be read yet — the apply waits for the volume addon to
  /// produce one — so what is kept is whether the cluster had a default at all. A cluster that
  /// arrived with one keeps it, and a mark read at undo time cannot say who put it there.
  @override
  Future<String?> capture(StepContext context) async =>
      _default(await _classes(context) ?? const <String, bool>{});

  @override
  Future<void> undo(StepContext context, String? captured) async {
    if (captured != null) {
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
      Command.observing('microk8s', <String>[
        'kubectl',
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

  String? _default(Map<String, bool> classes) {
    for (final MapEntry<String, bool> storageClass in classes.entries) {
      if (storageClass.value) {
        return storageClass.key;
      }
    }
    return null;
  }

  Future<void> _mark(StepContext context, String storageClass, bool isDefault) async {
    final List<String> argv = <String>[
      'microk8s',
      'kubectl',
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
    ];
    final CommandResult marked = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!marked.ok) {
      throw CommandFailed(argv: argv, exitCode: marked.exitCode, stderr: marked.stderr);
    }
  }

  /// The mark's name with the dots escaped, because a reading path splits on them.
  static final String _escapedAnnotation = annotation.replaceAll('.', r'\.');
}
