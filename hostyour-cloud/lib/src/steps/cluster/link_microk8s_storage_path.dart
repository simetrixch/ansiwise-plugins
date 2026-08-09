import 'package:ansiwise_api/ansiwise_api.dart';

/// Points the cluster's own volume directory at the data filesystem.
///
/// **A real directory already sitting there is moved aside and never written over.** The cluster may
/// already have written volumes into it, and replacing it with a link would leave that data with
/// nothing pointing at it and no note of where it went. It is renamed with the moment it was moved,
/// so it is still there to be looked at.
///
/// **A link pointing somewhere else is left alone unless the operator asks for it.** It is the only
/// thing saying where this cluster's volumes are, and repointing it silently would strand every one
/// of them. Asking for it by name is what says the operator knows.
final class LinkMicrok8sStoragePath extends IrreversibleStep {
  /// Points [microk8sStoragePath] at the answered storage directory, replacing a wrong link only
  /// under [force].
  const LinkMicrok8sStoragePath({required this.microk8sStoragePath, required this.force});

  /// Builds the step from what the program gave it.
  factory LinkMicrok8sStoragePath.fromArguments(Arguments arguments) => LinkMicrok8sStoragePath(
    microk8sStoragePath: arguments.text('microk8s_storage_path'),
    force: arguments.flag('force'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'microk8s_storage_path',
      kind: ArgumentKind.text,
      describes: "the directory the cluster's own volume provider writes into",
      required: false,
      defaultValue: defaultPath,
    ),
    ArgumentSpec(
      name: 'force',
      kind: ArgumentKind.flag,
      describes:
          'whether a link already pointing somewhere else may be repointed, which strands '
          'every volume under the place it pointed at',
      required: false,
      defaultValue: false,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  ///
  /// The same directory the step before it made, under the same name, or the link would point at
  /// somewhere nothing was created.
  static const List<String> answers = <String>['storage_directory'];

  /// Where the cluster's own volume provider writes.
  static const String defaultPath = '/var/snap/microk8s/common/default-storage';

  /// The directory the volume provider writes into.
  final String microk8sStoragePath;

  /// Whether a link pointing elsewhere may be repointed.
  final bool force;

  @override
  String get irreversibleReason =>
      'everything the cluster writes through the link lands on the data filesystem and stays there. '
      'Removing the link and moving the directory that was here back leaves that data behind, with '
      'nothing recording which volume any of it belonged to';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (context.answers.text('storage_directory').isEmpty) {
      return const CheckResult.satisfied(
        'this machine has no separate data filesystem, so the volume provider keeps its own '
        'directory',
      );
    }

    final String? target = await _linkTarget(context);
    if (target == context.answers.text('storage_directory')) {
      return CheckResult.satisfied(
        '$microk8sStoragePath points at ${context.answers.text('storage_directory')}',
      );
    }
    if (target != null && !force) {
      context.log.warn(
        '$microk8sStoragePath points at $target rather than at ${context.answers.text('storage_directory')}. It is left where '
        'it is: every volume this cluster has already handed out lives under $target, and '
        'repointing the link strands all of them. Set force to repoint it.',
      );
      return CheckResult.satisfied('$microk8sStoragePath points at $target and was left alone');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async => StepPlan.argv(<String>[
    'ln',
    '-s',
    context.answers.text('storage_directory'),
    microk8sStoragePath,
  ]);

  @override
  Future<void> apply(StepContext context) async {
    final String? target = await _linkTarget(context);
    if (target != null) {
      // Only reached under force, because the check answers satisfied otherwise.
      context.log.warn('repointing $microk8sStoragePath away from $target');
      await _mustRun(context, <String>['rm', microk8sStoragePath]);
    } else if (await _isRealDirectory(context)) {
      final String moved = '$microk8sStoragePath.orig.${_stampOfNow(context)}';
      context.log.info(
        '$microk8sStoragePath is a directory the cluster may already have written into — it is at '
        '$moved from now on',
      );
      await _mustRun(context, <String>['mv', microk8sStoragePath, moved]);
    }
    await _mustRun(context, <String>[
      'ln',
      '-s',
      context.answers.text('storage_directory'),
      microk8sStoragePath,
    ]);
  }

  /// Where the link points, or null when there is no link there.
  Future<String?> _linkTarget(StepContext context) async {
    final CommandResult isLink = await context.shell.run(
      Command.observing('test', <String>['-L', microk8sStoragePath]),
    );
    if (!isLink.ok) {
      return null;
    }
    final CommandResult target = await context.shell.run(
      Command.observing('readlink', <String>['-f', microk8sStoragePath]),
    );
    return target.ok && target.trimmed.isNotEmpty ? target.trimmed : null;
  }

  Future<bool> _isRealDirectory(StepContext context) async {
    final CommandResult directory = await context.shell.run(
      Command.observing('test', <String>['-d', microk8sStoragePath]),
    );
    return directory.ok;
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command(argv.first, argv.sublist(1)));
    if (!answer.ok) {
      throw CommandFailed(argv: argv, exitCode: answer.exitCode, stderr: answer.stderr);
    }
  }

  static String _stampOfNow(StepContext context) => context.clock
      .now()
      .toUtc()
      .toIso8601String()
      .replaceAll(RegExp(r'[:.]'), '')
      .split('Z')
      .first;
}
