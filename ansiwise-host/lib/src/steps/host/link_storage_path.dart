import 'package:ansiwise_core/ansiwise_core.dart';

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
final class LinkStoragePath extends IrreversibleStep {
  /// Points [linkPath] at the answered storage subdirectory, replacing a wrong link only under
  /// [force].
  const LinkStoragePath({required this.linkPath, required this.force});

  /// Builds the step from what the program gave it.
  factory LinkStoragePath.fromArguments(Arguments arguments) =>
      LinkStoragePath(linkPath: arguments.text('link_path'), force: arguments.flag('force'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // No default: where the volume provider writes is decided by how the cluster was installed, so
    // the program row states it.
    ArgumentSpec(
      name: 'link_path',
      kind: ArgumentKind.text,
      describes:
          "the path the cluster's volume provider writes through, which becomes a link to the "
          'storage subdirectory',
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
  static const List<String> answers = <String>['storage_subdirectory'];

  /// The path the volume provider writes through.
  final String linkPath;

  /// Whether a link pointing elsewhere may be repointed.
  final bool force;

  @override
  String get irreversibleReason =>
      'everything the cluster writes through the link lands on the data filesystem and stays there. '
      'Removing the link and moving the directory that was here back leaves that data behind, with '
      'nothing recording which volume any of it belonged to';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (context.answers.text('storage_subdirectory').isEmpty) {
      return const CheckResult.satisfied(
        'this machine has no separate data filesystem, so the volume provider keeps its own '
        'directory',
      );
    }

    final String? target = await _linkTarget(context);
    if (target == context.answers.text('storage_subdirectory')) {
      return CheckResult.satisfied(
        '$linkPath points at ${context.answers.text('storage_subdirectory')}',
      );
    }
    if (target != null && !force) {
      context.log.warn(
        '$linkPath points at $target rather than at ${context.answers.text('storage_subdirectory')}. '
        'It is left where it is: every volume this cluster has already handed out lives under '
        '$target, and repointing the link strands all of them. Set force to repoint it.',
      );
      return CheckResult.satisfied('$linkPath points at $target and was left alone');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['ln', '-s', context.answers.text('storage_subdirectory'), linkPath]);

  @override
  Future<void> apply(StepContext context) async {
    final String? target = await _linkTarget(context);
    if (target != null) {
      // Only reached under force, because the check answers satisfied otherwise.
      context.log.warn('repointing $linkPath away from $target');
      await _mustRun(context, <String>['rm', linkPath]);
    } else if (await _isRealDirectory(context)) {
      final String moved = '$linkPath.orig.${_stampOfNow(context)}';
      context.log.info(
        '$linkPath is a directory the cluster may already have written into — it is at '
        '$moved from now on',
      );
      await _mustRun(context, <String>['mv', linkPath, moved]);
    }
    await _mustRun(context, <String>[
      'ln',
      '-s',
      context.answers.text('storage_subdirectory'),
      linkPath,
    ]);
  }

  /// Where the link points, or null when there is no link there.
  Future<String?> _linkTarget(StepContext context) async {
    final CommandResult isLink = await context.shell.run(
      Command.observing('test', arguments: <String>['-L', linkPath]),
    );
    if (!isLink.ok) {
      return null;
    }
    final CommandResult target = await context.shell.run(
      Command.observing('readlink', arguments: <String>['-f', linkPath]),
    );
    return target.ok && target.trimmed.isNotEmpty ? target.trimmed : null;
  }

  Future<bool> _isRealDirectory(StepContext context) async {
    final CommandResult directory = await context.shell.run(
      Command.observing('test', arguments: <String>['-d', linkPath]),
    );
    return directory.ok;
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(
      Command.detailed(argv.first, arguments: argv.sublist(1), elevated: true),
    );
    if (!answer.ok) {
      throw CommandFailed(
        argv: argv,
        exitCode: answer.exitCode,
        stdout: answer.stdout,
        stderr: answer.stderr,
      );
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
