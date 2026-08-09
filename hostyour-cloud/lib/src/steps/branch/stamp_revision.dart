import 'package:ansiwise_api/ansiwise_api.dart';
import 'create_install_branch.dart';

/// Points every generator of this installation at this installation's own branch.
///
/// The manifests under `argocd/` name the branch they read from. On the trunk that is the trunk
/// itself, which is what makes the trunk a product tree rather than an installation. Here the value
/// becomes the branch this run is generating, so that everything an installation deploys is read
/// from the installation's own files.
///
/// **Three kinds of line carry a branch name, and only one of them is stamped.**
///
/// 1. An ordinary `revision:` or `targetRevision:` reading the trunk. This is the one that becomes
///    the fqdn.
/// 2. A line carrying the marker `set-domain:keep` as a trailing comment. It stays on the trunk on
///    purpose: what is marked is product that every installation shares — the member charts of the
///    tenant catalog — and retargeting those would point them at a branch that does not carry them.
/// 3. A line reading `__BOOKS_BRANCH__` instead of a branch name. It is not stamped here and it is
///    not marked either: the books of an installation stand on the branch of the cluster holding the
///    master role, which on a slave is not the branch being generated and is not something this step
///    can know. It is stamped later, from the cluster map. Nothing here has to skip it — it does not
///    carry the trunk's name, so it never matches.
///
/// **The value is rewritten and nothing else on the line.** The expression anchors on the key at the
/// start of the line and allows the YAML anchor some of these lines carry
/// (`targetRevision: &branch master`). The obvious alternative — replacing the word wherever it
/// occurs on the line — also rewrote the word inside a trailing comment, and left an installation
/// branch explaining itself with a sentence its own code contradicted.
final class StampRevision extends ReversibleStep<List<String>> {
  /// Retargets every generator under the manifest tree from [trunk] to this run's own branch.
  const StampRevision({required this.repository, required this.trunk});

  /// Builds the step from what the program gave it.
  factory StampRevision.fromArguments(Arguments arguments) =>
      StampRevision(repository: arguments.text('repository'), trunk: arguments.text('trunk'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout this installation is generated in',
    ),
    ArgumentSpec(
      name: 'trunk',
      kind: ArgumentKind.text,
      describes: 'the product branch these generators read from before they are stamped',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['fqdn'];

  /// The directory holding the manifests that name a branch.
  ///
  /// Layout of the tree being generated rather than a value of this installation: every installation
  /// keeps its generators in the same place, so a program that could point this elsewhere would only
  /// be able to point it somewhere wrong.
  static const String tree = 'argocd';

  /// The trailing comment that exempts a line from this stamp.
  static const String keepMarker = 'set-domain:keep';

  /// The checkout being stamped.
  final String repository;

  /// The branch they read from before.
  final String trunk;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? head = await _head(context);
    if (head == trunk) {
      return CheckResult.blocked(
        'the trunk "$trunk" is checked out, and stamping it would put this installation onto the '
        'branch every other installation is cut from — cut the branch first',
      );
    }

    final Map<String, String> left = await _unstamped(context);
    if (left.isEmpty) {
      return CheckResult.satisfied(
        'every revision under $tree/ reads ${CreateInstallBranch.branchIn(context)}',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String fqdn = CreateInstallBranch.branchIn(context);
    final Map<String, String> left = await _unstamped(context);
    for (final String path in left.keys) {
      context.log.info('$path would be retargeted from $trunk to $fqdn');
    }
    // One step here rewrites many files and a plan carries one path, so the path is the tree and the
    // difference is the set of lines that change — which is what an operator reads a plan for.
    return StepPlan.diff(
      '$repository/$tree',
      before: left.values.join('\n'),
      after: left.values.map((String line) => _stamped(line, fqdn)).join('\n'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String fqdn = CreateInstallBranch.branchIn(context);
    for (final String path in (await _unstamped(context)).keys) {
      final String full = '$repository/$path';
      final String before = await context.files.read(full);
      final String after = before.split('\n').map((String line) => _stamped(line, fqdn)).join('\n');
      if (after != before) {
        await context.files.write(full, after, mode: _trackedFile);
      }
    }
  }

  /// Which manifests this run is about to retarget, as the checkout names them.
  ///
  /// Read before apply, because afterwards no line under the tree names the trunk any more and
  /// nothing says which files got there by this step. Restoring the whole of [tree] instead would
  /// take back every other change standing in it — the books placeholder a later step stamps, and
  /// anything an operator edited on the branch.
  @override
  Future<List<String>> capture(StepContext context) async =>
      (await _unstamped(context)).keys.toList();

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    if (captured.isEmpty) {
      return;
    }
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

  /// Every line still naming the trunk that this step would rewrite, by the file it is in.
  ///
  /// This is also the postcondition. `sed` exits zero whether or not its expression matched, and
  /// every failure of that shape reported success while the file kept what it always held — so the
  /// answer here comes from reading the files back rather than from a command having run. A file
  /// whose lines are all stamped, marked or reading the books placeholder contributes nothing, which
  /// is why a second run of this step finds nothing to do.
  Future<Map<String, String>> _unstamped(StepContext context) async {
    final String fqdn = CreateInstallBranch.branchIn(context);
    final Map<String, String> left = <String, String>{};
    for (final String path in await _candidates(context)) {
      // A tracked path the search names is not necessarily a file that is there: reducing the branch
      // to one stage removes whole manifest trees while git goes on tracking them until the commit.
      final String full = '$repository/$path';
      if (!await context.files.exists(full)) {
        continue;
      }
      final String content = await context.files.read(full);
      final List<String> lines = content
          .split('\n')
          .where((String line) => _stamped(line, fqdn) != line)
          .toList();
      if (lines.isNotEmpty) {
        left[path] = lines.join('\n');
      }
    }
    return left;
  }

  /// The tracked files under the manifest tree that name the trunk at all.
  ///
  /// A content search first, so that only the few files that can possibly be in the answer are ever
  /// opened. Every other file under the tree is never read.
  Future<List<String>> _candidates(StepContext context) async {
    final CommandResult found = await context.shell.run(
      Command.observing('git', <String>[
        '-C',
        repository,
        'grep',
        '--full-name',
        '--files-with-matches',
        '--fixed-strings',
        '-e',
        trunk,
        '--',
        tree,
      ]),
    );
    // A content search answers one when it found nothing, which is an answer and not a failure.
    // Anything above that is a search that could not be carried out, and treating it as "no files"
    // would report a tree as stamped because nobody could look at it.
    if (found.exitCode > 1) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'grep', trunk, '--', tree],
        exitCode: found.exitCode,
        stderr: found.stderr,
      );
    }
    return found.trimmed.isEmpty
        ? const <String>[]
        : found.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  /// [line] with its revision value retargeted to [fqdn], or [line] itself when it is not one to
  /// stamp.
  String _stamped(String line, String fqdn) {
    if (line.contains(keepMarker)) {
      return line;
    }
    return line.replaceFirstMapped(_pattern, (Match match) => '${match.group(1)}$fqdn');
  }

  /// The key at the start of the line, the anchor some lines carry, and then the value itself.
  ///
  /// The value stops at its own word: the lookahead refuses a longer branch name that merely begins
  /// with the trunk's, which a word boundary would have let through — `master-of-record` is not the
  /// trunk.
  RegExp get _pattern => RegExp(
    '^([ \\t]*(?:-[ \\t]+)?(?:revision|targetRevision):[ \\t]*(?:&[^ \\t]+[ \\t]+)?)'
    '${RegExp.escape(trunk)}(?![\\w./-])',
  );

  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  /// `0644` — a manifest everything in the tree reads.
  static const int _trackedFile = 0x1a4;
}
