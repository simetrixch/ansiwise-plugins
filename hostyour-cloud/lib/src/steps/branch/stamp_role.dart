import 'package:ansiwise_api/ansiwise_api.dart';

import '../../branch/role_pruning.dart';

/// Reduces the branch to the one stage and the one role this installation is.
///
/// The trunk is generic in two directions at once. It carries all three stages, because it is the
/// product tree every installation is cut from; and it carries the books — the cluster maps and the
/// registrations — because it does not know which cluster will read them. An installation is
/// neither: it is exactly one stage, and exactly one role.
///
/// **One stage, and this is not tidying.** Removing the other two stages' values, manifest trees and
/// per-app overrides is what makes it impossible for the stage a chart renders, the paths its
/// secrets are read from and the names of its releases to disagree with one another. There is no
/// second stage left for anything to accidentally resolve to. The stage is also the one thing that
/// is never derived from the domain: an installation reached at a public name runs its stage without
/// that name ever saying so.
///
/// **The role decides whether this branch keeps the books.** They live on the branch of the cluster
/// holding the master part, because that is the only cluster whose deployment reads them — it hosts
/// its slaves' instances too. A slave's branch is pruned of both, and a second copy there would not
/// be merely redundant: it goes stale the moment anything writes to the master's branch, and a stale
/// book is worse than none.
///
/// **The role is never guessed.** A run without an answer, on a branch without a map, cannot decide
/// this — and guessing wrongly deletes an installation's registrations and every cluster map it
/// holds. So the map has to be on the branch and has to agree with what this run was told, or
/// nothing is removed at all.
final class StampRole extends ReversibleStep<List<String>> {
  /// Reduces the checkout at [repository] to the one stage and role this run was told about.
  const StampRole({
    required this.repository,
    required this.stages,
    required this.trunk,
    this.stageFiles = RolePruning.defaultStageFiles,
    this.stageTrees = RolePruning.defaultStageTrees,
    this.booksTree = RolePruning.defaultBooksTree,
    this.mapsTree = RolePruning.defaultMapsTree,
  });

  /// Builds the step from what the program gave it.
  factory StampRole.fromArguments(Arguments arguments) => StampRole(
    repository: arguments.text('repository'),
    stages: arguments.textList('stages'),
    trunk: arguments.text('trunk'),
    stageFiles: arguments.textList('stage_files'),
    stageTrees: arguments.textList('stage_trees'),
    booksTree: arguments.text('books_tree'),
    mapsTree: arguments.text('maps_tree'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
    ArgumentSpec(
      name: 'stages',
      kind: ArgumentKind.textList,
      describes: 'every stage the product carries, of which the other two are removed',
    ),
    ArgumentSpec(
      name: 'trunk',
      kind: ArgumentKind.text,
      describes: 'the product branch, which this refuses to reduce',
    ),
    ArgumentSpec(
      name: 'stage_files',
      kind: ArgumentKind.textList,
      describes:
          'the files a stage owns, as regular expressions anchored at the top of the checkout and '
          'carrying the <stage> slot',
      required: false,
      defaultValue: RolePruning.defaultStageFiles,
    ),
    ArgumentSpec(
      name: 'stage_trees',
      kind: ArgumentKind.textList,
      describes:
          'the directories a stage owns, as plain paths carrying the <stage> slot — removed file '
          'by file, and then the emptied directory itself',
      required: false,
      defaultValue: RolePruning.defaultStageTrees,
    ),
    ArgumentSpec(
      name: 'books_tree',
      kind: ArgumentKind.text,
      describes:
          'the directory the books of onboarded units stand in, which only a master\'s branch '
          'keeps',
      required: false,
      defaultValue: RolePruning.defaultBooksTree,
    ),
    ArgumentSpec(
      name: 'maps_tree',
      kind: ArgumentKind.text,
      describes:
          'the directory the cluster maps stand in, of which a slave\'s branch keeps only its own',
      required: false,
      defaultValue: RolePruning.defaultMapsTree,
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['fqdn', 'stage', 'role'];

  /// The role that keeps the books.
  static const String master = 'master';

  /// The role that keeps none of them.
  static const String slave = 'slave';

  /// The checkout being reduced.
  final String repository;

  /// Every stage the product carries.
  final List<String> stages;

  /// The product branch, which this step refuses to reduce.
  final String trunk;

  /// The files a stage owns, as regular expressions carrying the `<stage>` slot.
  final List<String> stageFiles;

  /// The directories a stage owns, as plain paths carrying the `<stage>` slot.
  final List<String> stageTrees;

  /// The directory the books stand in, which only a master's branch keeps.
  final String booksTree;

  /// The directory the cluster maps stand in.
  final String mapsTree;

  /// Where the map of this cluster stands, relative to the top of the checkout.
  String mapPathFor(StepContext context) => '$mapsTree/${context.answers.text('fqdn')}.yaml';

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? head = await _head(context);
    if (head == trunk) {
      return CheckResult.blocked(
        'the trunk "$trunk" is checked out, and reducing it would leave the tree every other '
        'installation is cut from carrying one stage and one role — cut the branch first',
      );
    }

    final String? refusal = await _mapRefusal(context);
    if (refusal != null) {
      return CheckResult.blocked(refusal);
    }

    final List<String> left = await _toRemove(context);
    if (left.isEmpty) {
      return CheckResult.satisfied(
        'this branch carries ${context.answers.text('stage')} and what a '
        '${context.answers.text('role')} carries, and nothing else',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final List<String> left = await _toRemove(context);
    for (final String path in left) {
      context.log.debug('$path would be removed');
    }
    // One step here removes many files and a plan carries one path, so the path is the checkout and
    // the difference is what would no longer be in it.
    return StepPlan.diff(repository, before: left.join('\n'), after: '');
  }

  @override
  Future<void> apply(StepContext context) async {
    // The stages first. What the role decides is read against a tree that already carries exactly
    // one stage, and the two orders are not interchangeable for anything that walks the stage trees.
    for (final String path in await _toRemove(context)) {
      await context.files.delete('$repository/$path');
    }

    final String kept = context.answers.text('stage');
    for (final String other in stages.where((String each) => each != kept)) {
      for (final String tree in stageTrees) {
        await _removeEmptied(context, RolePruning.filled(tree, other));
      }
    }
    if (context.answers.text('role') == slave) {
      await _removeEmptied(context, booksTree);
    }
  }

  /// Which paths this run is about to remove, as the checkout names them.
  ///
  /// Read before apply, because afterwards they are gone and nothing on the branch says which of
  /// them this run took away and which an earlier one had already pruned. An undo restores exactly
  /// these, and a path this step never reached is restored to what it already held, since this step
  /// removes files and changes the content of none.
  @override
  Future<List<String>> capture(StepContext context) => _toRemove(context);

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    if (captured.isEmpty) {
      return;
    }
    // Restoring the files brings back the directories they stand in, so nothing else has to be
    // undone.
    final List<String> argv = <String>['-C', repository, 'checkout', '--', ...captured];
    final CommandResult restored = await context.shell.run(Command('git', argv));
    if (!restored.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: restored.exitCode,
        stderr: restored.stderr,
      );
    }
  }

  /// Why this branch cannot be reduced yet, or null when it can.
  ///
  /// The map is the branch's own file and the branch is named for the domain, so this stage needs
  /// nothing else to know which cluster it is looking at. What it will not do is proceed without it.
  Future<String?> _mapRefusal(StepContext context) async {
    final String mapPath = mapPathFor(context);
    final String full = '$repository/$mapPath';
    if (!await context.files.exists(full)) {
      return '$mapPath is not on this branch, and what a branch keeps cannot be decided without it '
          '— pruning the wrong way deletes this installation\'s registrations and cluster maps';
    }

    final Map<String, String> stated = _fields(await context.files.read(full));
    final String? statedRole = stated['role'];
    final String? statedStage = stated['stage'];
    final String role = context.answers.text('role');
    final String stage = context.answers.text('stage');

    if (statedRole != master && statedRole != slave) {
      return '$mapPath states the role as "${statedRole ?? 'nothing'}", and a cluster is '
          '$master or $slave';
    }
    if (statedRole != role) {
      return '$mapPath states the role as "$statedRole" and this run was told "$role"';
    }
    if (statedStage != stage) {
      return '$mapPath states the stage as "${statedStage ?? 'nothing'}" and this run was told '
          '"$stage"';
    }
    return null;
  }

  /// Everything on this branch that this installation does not carry, and is still there.
  Future<List<String>> _toRemove(StepContext context) async => <String>[
    for (final String path in await _prunable(context))
      if (await context.files.exists('$repository/$path')) path,
  ];

  /// Every tracked path this installation does not carry, whether or not it is still there.
  ///
  /// Read from what git holds rather than from the tree, because the tree is what this step changes:
  /// the same list has to come back on a second run, when the files are already gone, or the step
  /// could not tell "already done" from "nothing to do".
  Future<List<String>> _prunable(StepContext context) async {
    final RolePruning rule = pruningFor(context);
    return <String>[
      for (final String path in await _tracked(context))
        if (rule.reasonFor(path) != null) path,
    ];
  }

  /// The rule this run prunes by.
  ///
  /// The gate applies the SAME rule to a tree it walked, in order to decide whether the `derived:`
  /// section of branch-classes.yaml names the paths a run would really resolve. It used to state
  /// that rule a second time — in string operations where this one was regular expressions — and
  /// nothing compared the two.
  RolePruning pruningFor(StepContext context) => RolePruning(
    stage: context.answers.text('stage'),
    stages: stages,
    isSlave: context.answers.text('role') == slave,
    ownMap: _relativeToRepository(mapPathFor(context)),
    stageFiles: stageFiles,
    stageTrees: stageTrees,
    booksTree: booksTree,
    mapsTree: mapsTree,
  );

  /// [full] as the checkout names it, because the pruning rule speaks in tracked paths.
  String _relativeToRepository(String full) =>
      full.startsWith('$repository/') ? full.substring(repository.length + 1) : full;

  Future<List<String>> _tracked(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'ls-files', '--full-name']),
    );
    if (!listed.ok) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'ls-files', '--full-name'],
        exitCode: listed.exitCode,
        stderr: listed.stderr,
      );
    }
    return listed.trimmed.isEmpty
        ? const <String>[]
        : listed.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  /// Removes [relative] when nothing is left in it.
  ///
  /// git holds files and not directories, so removing every file of a stage tree leaves the tree
  /// itself standing. What is asked for is the emptied directory, which is why one that still holds
  /// something is left exactly as it is.
  Future<void> _removeEmptied(StepContext context, String relative) async {
    final String full = '$repository/$relative';
    if (!await context.files.exists(full)) {
      return;
    }
    if ((await context.files.list(full)).isNotEmpty) {
      return;
    }
    await context.files.delete(full);
  }

  /// The top-level `key: value` lines of the map.
  static Map<String, String> _fields(String content) {
    final Map<String, String> fields = <String, String>{};
    for (final String line in content.split('\n')) {
      if (line.startsWith('#') || line.startsWith(' ') || line.startsWith('\t')) {
        continue;
      }
      final int colon = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      fields[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
    }
    return fields;
  }

  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }
}
