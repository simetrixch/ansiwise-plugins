import 'package:ansiwise_api/ansiwise_api.dart';

import '../../branch/fqdn_selection.dart';
import 'create_install_branch.dart';

/// Puts this installation's real domain where the trunk carries a placeholder.
///
/// The trunk is domain-agnostic: it says `example.invalid` everywhere an installation says its own
/// name, so that nothing on the trunk belongs to anybody and every installation is cut from the same
/// tree. This step is what turns one copy of that tree into one installation.
///
/// **Only the literal is replaced, and that is the whole rule.** There is nothing here that
/// recognises a domain, and adding one would be the defect. A domain used as an illustration —
/// `example.com` in a comment, a help string, a user interface placeholder or a test fixture — is a
/// different literal, so it is never matched and never has to be told apart from a value. The same
/// holds for a label key of the form `digitacloud.app/<x>`: that is a namespace in the Kubernetes
/// convention, a product identifier nothing resolves and nothing addresses, and it survives for
/// exactly the same reason. A stamp that matched "anything domain-shaped" would rewrite both, and
/// renaming a label key reaches every selector and every role binding at once.
///
/// **Scripts are excluded as a class, and that is load-bearing.** The placeholder inside a script is
/// never installation state — it is a guard, a fixture or a comment. Two of them were rewritten
/// before the exclusion existed: a script whose own guard compared against the placeholder came out
/// refusing the very domain it was being installed for, and a library whose empty-value test read
/// the placeholder came out producing hosts with no domain at all. Installation state lives in
/// values and config files.
///
/// **A script is recognised by what it is, not by what it is called.** A suffix list alone lets an
/// extensionless script through, and the stamp reached into a script again. The first line answers
/// for every one of those; the two suffixes stay for PowerShell, which carries no such line.
///
/// **The content search runs first and the first line second.** Only a file that carries the
/// placeholder can be in the answer, and that is a few dozen of several hundred. Testing the first
/// line of every tracked file instead costs one open per file, and that ordering was measured at
/// eight and a half seconds per call on Windows for a function every install and four checks run.
final class StampFqdn extends ReversibleStep {
  /// Replaces the placeholder with this run's own domain everywhere in [repository] that holds it.
  const StampFqdn({required this.repository, required this.trunk});

  /// Builds the step from what the program gave it.
  factory StampFqdn.fromArguments(Arguments arguments) =>
      StampFqdn(repository: arguments.text('repository'), trunk: arguments.text('trunk'));

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

  /// What the trunk carries in place of a domain.
  static const String placeholder = FqdnSelection.placeholder;

  /// The checkout being stamped.
  final String repository;

  /// The product branch, which this step refuses to stamp.
  final String trunk;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? head = await _head(context);
    if (head == trunk) {
      return CheckResult.blocked(
        'the trunk "$trunk" is checked out, and stamping a domain into it would hand that domain to '
        'every installation cut from it afterwards — cut the branch first',
      );
    }

    final Map<String, String> left = await _stampable(context);
    if (left.isEmpty) {
      return const CheckResult.satisfied(
        'no file that holds installation state carries $placeholder',
      );
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String fqdn = CreateInstallBranch.branchIn(context);
    final Map<String, String> left = await _stampable(context);
    for (final String path in left.keys) {
      context.log.info('$path would have $placeholder replaced by $fqdn');
    }
    final List<String> lines = <String>[
      for (final String content in left.values)
        ...content.split('\n').where((String line) => line.contains(placeholder)),
    ];
    // One step here rewrites many files and a plan carries one path, so the path is the checkout and
    // the difference is the set of lines that change.
    return StepPlan.diff(
      repository,
      before: lines.join('\n'),
      after: lines.map((String line) => _stamped(line, fqdn)).join('\n'),
    );
  }

  @override
  Future<void> apply(StepContext context) async {
    final String fqdn = CreateInstallBranch.branchIn(context);
    final Map<String, String> stampable = await _stampable(context);
    for (final MapEntry<String, String> file in stampable.entries) {
      await context.files.write(
        '$repository/${file.key}',
        _stamped(file.value, fqdn),
        mode: _trackedFile,
      );
    }
  }

  @override
  Future<void> undo(StepContext context) async {
    // What this step wrote is what now carries the domain, found the same way it found what to
    // write. Nothing on a branch freshly cut from the trunk carries it otherwise — that is what
    // makes the trunk domain-agnostic.
    final List<String> written = <String>[
      for (final String path in await _search(context, CreateInstallBranch.branchIn(context)))
        if (!selection.excludesByName(path)) path,
    ];
    if (written.isEmpty) {
      return;
    }
    final List<String> argv = <String>['-C', repository, 'checkout', '--', ...written];
    final CommandResult restored = await context.shell.run(Command('git', argv));
    if (!restored.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: restored.exitCode,
        stderr: restored.stderr,
      );
    }
  }

  /// The files that hold installation state and still carry the placeholder, with their content.
  ///
  /// This is also the postcondition: it is read from the files rather than from a command having
  /// returned zero, so a rewrite that silently matched nothing cannot report itself as done.
  ///
  /// The order of the tests is the point. The content search has already narrowed several hundred
  /// tracked files to the few that can be in the answer; the name tests cost nothing and run next;
  /// the file is opened once, and only a file that really carries the placeholder is asked what it
  /// is.
  Future<Map<String, String>> _stampable(StepContext context) async {
    final Map<String, String> stampable = <String, String>{};
    for (final String path in await _search(context, placeholder)) {
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
      // The whole rule, in one call. What the name test above already settled is settled again here
      // and costs nothing; what it could not settle — the file really carrying the placeholder, and
      // a first line that makes it a script whatever it is called — is settled by the same object
      // the gate asks, so the two cannot answer differently.
      if (!selection.selects(path, content)) {
        continue;
      }
      stampable[path] = content;
    }
    return stampable;
  }

  /// Every tracked file carrying [literal], as paths relative to the top of the checkout.
  Future<List<String>> _search(StepContext context, String literal) async {
    final CommandResult found = await context.shell.run(
      Command.observing('git', <String>[
        '-C',
        repository,
        'grep',
        '--full-name',
        '--files-with-matches',
        '--fixed-strings',
        '-e',
        literal,
      ]),
    );
    // A content search answers one when it found nothing, which is an answer and not a failure.
    // Anything above that is a search that could not be carried out, and treating it as "no files"
    // would report a tree as stamped because nobody could look at it.
    if (found.exitCode > 1) {
      throw CommandFailed(
        argv: <String>['git', '-C', repository, 'grep', literal],
        exitCode: found.exitCode,
        stderr: found.stderr,
      );
    }
    return found.trimmed.isEmpty
        ? const <String>[]
        : found.trimmed.split('\n').map((String line) => line.trim()).toList();
  }

  String _stamped(String content, String fqdn) => content.replaceAll(placeholder, fqdn);

  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    return answer.ok && answer.trimmed.isNotEmpty ? answer.trimmed : null;
  }

  /// `0644` — a values or config file everything in the tree reads.
  static const int _trackedFile = 0x1a4;
}
