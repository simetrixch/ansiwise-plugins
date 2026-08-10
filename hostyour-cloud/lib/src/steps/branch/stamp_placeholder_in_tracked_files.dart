import 'package:ansiwise_api/ansiwise_api.dart';

import '../../branch/fqdn_selection.dart';
import 'create_install_branch.dart';

/// Puts this installation's own branch where the trunk carries a placeholder.
///
/// The trunk is domain-agnostic and installation-agnostic: it carries a stand-in everywhere an
/// installation carries something of its own, so that nothing on the trunk belongs to anybody and
/// every installation is cut from the same tree. This step is what turns one copy of that tree into
/// one installation, and it does it twice — once for the domain the installation answers on, and
/// once for the branch its generators read from, where the stand-in is the trunk's own name.
///
/// **The set of files is FOUND, not named.** A content search over the tracked files answers with
/// the few that can possibly be in it, and git is what puts them back: an undo restores exactly the
/// paths this run rewrote and no other.
///
/// **Only the literal is replaced, and that is the whole rule.** There is nothing here that
/// recognises a domain or a branch, and adding one would be the defect. A value used as an
/// illustration — `example.com` in a comment, a help string, a user interface placeholder or a test
/// fixture — is a different literal, so it is never matched and never has to be told apart from a
/// value. The same holds for a label key of the form `digitacloud.app/<x>`: that is a namespace in
/// the Kubernetes convention, a product identifier nothing resolves and nothing addresses, and it
/// survives for exactly the same reason. A stamp that matched "anything domain-shaped" would rewrite
/// both, and renaming a label key reaches every selector and every role binding at once.
///
/// **[keys] is what narrows a common word to the value of a setting.** A branch name is an ordinary
/// English word that stands all over a tree, so replacing it wherever it occurs would rewrite it
/// inside a trailing comment and leave an installation branch explaining itself with a sentence its
/// own code contradicted. Where [keys] are named, the expression anchors on one of them at the start
/// of the line, allows the YAML anchor some of those lines carry (`targetRevision: &branch master`),
/// and rewrites the value alone. The lookahead after the literal refuses a longer value that merely
/// begins with it — `master-of-record` is not the trunk. Where no [keys] are named, every occurrence
/// on the line is the value, which is what a domain placeholder is.
///
/// **A line carrying [keepMarker] is never stamped.** What is marked is product that every
/// installation shares — the member charts of the tenant catalog — and retargeting those would point
/// them at a branch that does not carry them.
///
/// **Scripts and product material are excluded as a class, and that is load-bearing.** The
/// placeholder inside a script is never installation state — it is a guard, a fixture or a comment.
/// Two of them were rewritten before the exclusion existed: a script whose own guard compared against
/// the placeholder came out refusing the very domain it was being installed for, and a library whose
/// empty-value test read the placeholder came out producing hosts with no domain at all. Installation
/// state lives in values and config files.
///
/// **A script is recognised by what it is, not by what it is called.** A suffix list alone lets an
/// extensionless script through, and the stamp reached into a script again. The first line answers
/// for every one of those; the two suffixes stay for PowerShell, which carries no such line.
///
/// **The content search runs first and the first line second.** Only a file that carries the literal
/// can be in the answer, and that is a few dozen of several hundred. Testing the first line of every
/// tracked file instead costs one open per file, and that ordering was measured at eight and a half
/// seconds per call on Windows for a function every install and four checks run.
///
/// **The answer is read from the files rather than from a command having returned zero.** `sed`
/// exits zero whether or not its expression matched, and every failure of that shape reported success
/// while the file kept what it always held. A rewrite that silently matched nothing cannot report
/// itself as done here, and a second run finds nothing left to do.
final class StampPlaceholderInTrackedFiles extends ReversibleStep<List<String>> {
  /// Replaces [placeholder] with this run's own branch everywhere in [repository] that holds it.
  const StampPlaceholderInTrackedFiles({
    required this.repository,
    required this.trunk,
    required this.placeholder,
    required this.tree,
    required this.keys,
  });

  /// Builds the step from what the program gave it.
  factory StampPlaceholderInTrackedFiles.fromArguments(Arguments arguments) =>
      StampPlaceholderInTrackedFiles(
        repository: arguments.text('repository'),
        trunk: arguments.text('trunk'),
        placeholder: arguments.text('placeholder'),
        tree: arguments.text('tree'),
        keys: arguments.textList('keys'),
      );

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
      describes: 'the product branch, which this refuses to stamp',
    ),
    ArgumentSpec(
      name: 'placeholder',
      kind: ArgumentKind.text,
      describes:
          'the literal the trunk carries where an installation carries its own branch, which is '
          "the trunk's own name where the generators name the branch they read from",
    ),
    ArgumentSpec(
      name: 'tree',
      kind: ArgumentKind.text,
      describes:
          'the directory the search is limited to, or empty for the whole checkout — a layout of '
          'the tree being generated rather than a value of this installation',
      required: false,
      defaultValue: '',
    ),
    ArgumentSpec(
      name: 'keys',
      kind: ArgumentKind.textList,
      describes:
          'the keys whose value is replaced, or empty where every occurrence on the line is the '
          'value — a common word that also stands in prose needs the key in front of it',
      required: false,
      defaultValue: <String>[],
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['fqdn'];

  /// Which files this stamp rewrites, as a rule with no ports and no context.
  ///
  /// The gate applies the SAME object to the tree it walks, in order to decide whether
  /// branch-classes.yaml agrees with what would really happen here. It used to restate the rule
  /// instead, and a changed exclusion left every probe over there green while it certified a stamp
  /// it was no longer describing.
  static const FqdnSelection selection = FqdnSelection();

  /// The trailing comment that exempts a line from every stamp.
  static const String keepMarker = 'set-domain:keep';

  /// The checkout being stamped.
  final String repository;

  /// The product branch, which this step refuses to stamp.
  final String trunk;

  /// What the trunk carries where this installation carries its own branch.
  final String placeholder;

  /// The directory the search is limited to, or empty for the whole checkout.
  final String tree;

  /// The keys whose value is replaced, or empty where every occurrence on the line is.
  final List<String> keys;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? head = await _head(context);
    if (head == trunk) {
      return CheckResult.blocked(
        'the trunk "$trunk" is checked out, and stamping it would hand this installation\'s own '
        'values to every installation cut from it afterwards — cut the branch first',
      );
    }

    final Map<String, String> left = await _stampable(context);
    if (left.isEmpty) {
      return CheckResult.satisfied(
        'no file $_under that holds installation state carries $placeholder',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String branch = CreateInstallBranch.branchIn(context);
    final Map<String, String> left = await _stampable(context);
    for (final String path in left.keys) {
      context.log.info('$path would have $placeholder replaced by $branch');
    }
    final List<String> lines = <String>[
      for (final String content in left.values) ..._changing(content, branch),
    ];
    // One step here rewrites many files and a plan carries one path, so the path is the tree and the
    // difference is the set of lines that change — which is what an operator reads a plan for.
    return StepPlan.diff(
      _where,
      before: lines.join('\n'),
      after: lines.map((String line) => _stamped(line, branch)).join('\n'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String branch = CreateInstallBranch.branchIn(context);
    final Map<String, String> stampable = await _stampable(context);
    for (final MapEntry<String, String> file in stampable.entries) {
      final String after = file.value
          .split('\n')
          .map((String line) => _stamped(line, branch))
          .join('\n');
      await context.files.write('$repository/${file.key}', after, mode: _trackedFile);
    }
  }

  /// Which files this run is about to stamp, as the checkout names them.
  ///
  /// Read before apply, because afterwards they carry the branch and a search for the branch answers
  /// with every file that carries it — the ones this step wrote and any that already held it.
  /// Restoring the whole tree instead would take back every other change standing in it, including
  /// what a later step stamps and anything an operator edited on the branch.
  @override
  Future<List<String>> capture(StepContext context) async =>
      (await _stampable(context)).keys.toList();

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

  /// The files that hold installation state and still carry a line this stamp would rewrite.
  ///
  /// This is also the postcondition: it is read from the files rather than from a command having
  /// returned zero, so a rewrite that silently matched nothing cannot report itself as done.
  ///
  /// The order of the tests is the point. The content search has already narrowed several hundred
  /// tracked files to the few that can be in the answer; the name tests cost nothing and run next;
  /// the file is opened once, and only a file that really carries the literal is asked what it is.
  Future<Map<String, String>> _stampable(StepContext context) async {
    final String branch = CreateInstallBranch.branchIn(context);
    final Map<String, String> stampable = <String, String>{};
    for (final String path in await _search(context)) {
      if (selection.excludesByName(path)) {
        continue;
      }
      // A tracked path the search names is not necessarily a file that is there: reducing the branch
      // to one stage removes whole trees while git goes on tracking them until the commit.
      final String full = '$repository/$path';
      if (!await context.files.exists(full)) {
        continue;
      }
      final String content = await context.files.read(full);
      // What the name test above already settled is settled again here and costs nothing; what it
      // could not settle — a first line that makes this a script whatever it is called — is settled
      // by the same object the gate asks, so the two cannot answer differently.
      if (!selection.holdsInstallationState(path, content)) {
        continue;
      }
      if (_changing(content, branch).isEmpty) {
        continue;
      }
      stampable[path] = content;
    }
    return stampable;
  }

  /// Every tracked file carrying [placeholder], as paths relative to the top of the checkout.
  Future<List<String>> _search(StepContext context) async {
    final List<String> argv = <String>[
      '-C',
      repository,
      'grep',
      '--full-name',
      '--files-with-matches',
      '--fixed-strings',
      '-e',
      placeholder,
      if (tree.isNotEmpty) ...<String>['--', tree],
    ];
    final CommandResult found = await context.shell.run(Command.observing('git', argv));
    // A content search answers one when it found nothing, which is an answer and not a failure.
    // Anything above that is a search that could not be carried out, and treating it as "no files"
    // would report a tree as stamped because nobody could look at it.
    if (found.exitCode > 1) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: found.exitCode,
        stderr: found.stderr,
      );
    }
    return found.trimmed.isEmpty
        ? const <String>[]
        : found.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  /// The lines of [content] this stamp would rewrite, in the order they stand in.
  List<String> _changing(String content, String branch) => <String>[
    for (final String line in content.split('\n'))
      if (_stamped(line, branch) != line) line,
  ];

  /// [line] with its value replaced by [branch], or [line] itself when it is not one to stamp.
  String _stamped(String line, String branch) {
    if (line.contains(keepMarker)) {
      return line;
    }
    if (keys.isEmpty) {
      return line.replaceAll(placeholder, branch);
    }
    return line.replaceFirstMapped(_pattern, (Match match) => '${match.group(1)}$branch');
  }

  /// One of [keys] at the start of the line, the anchor some lines carry, and then the value itself.
  ///
  /// The value stops at its own word: the lookahead refuses a longer value that merely begins with
  /// the literal, which a word boundary would have let through.
  RegExp get _pattern => RegExp(
    '^([ \\t]*(?:-[ \\t]+)?(?:${keys.map(RegExp.escape).join('|')}):[ \\t]*'
    '(?:&[^ \\t]+[ \\t]+)?)${RegExp.escape(placeholder)}(?![\\w./-])',
  );

  /// The one path a plan carries for a step that rewrites many files.
  String get _where => tree.isEmpty ? repository : '$repository/$tree';

  /// How a message names the part of the checkout this row is about.
  String get _under => tree.isEmpty ? 'in the checkout' : 'under $tree/';

  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  /// `0644` — a values, config or manifest file everything in the tree reads.
  static const int _trackedFile = 0x1a4;
}
