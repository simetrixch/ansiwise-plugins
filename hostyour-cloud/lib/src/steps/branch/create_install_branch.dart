import 'package:ansiwise_api/ansiwise_api.dart';

/// Cuts the branch this installation is generated on, before a single byte is stamped into it.
///
/// **The order is the safety property, not a convenience.** The trunk carries the placeholder
/// `example.invalid` and no customer's domain, and it is what every future installation is cut
/// from. If anything were stamped before the branch existed, one run would put a real domain onto
/// the trunk and every installation cut afterwards would inherit it. So the branch is created first,
/// and every stamping step refuses while the trunk is checked out — one property, guarded from both
/// ends.
///
/// **On the branch this step is a no-op, and on the trunk it never resets anything.** Re-running the
/// whole program on an existing installation branch is the normal repeat path: a merge from the
/// trunk brings back every placeholder, and the stamps are re-run in place. What this must never do
/// is throw away an existing branch to make room for a new one, so a branch that already exists is
/// reported rather than replaced.
final class CreateInstallBranch extends ReversibleStep {
  /// Cuts the branch of this run's domain from [trunk] in the checkout at [repository].
  const CreateInstallBranch({required this.repository, required this.trunk});

  /// Builds the step from what the program gave it.
  factory CreateInstallBranch.fromArguments(Arguments arguments) =>
      CreateInstallBranch(repository: arguments.text('repository'), trunk: arguments.text('trunk'));

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
      describes: 'the product branch this installation is cut from',
    ),
  ];

  /// The answers this step reads, which is what its registry entry declares.
  static const List<String> answers = <String>['fqdn'];

  /// The value the trunk carries in place of a real domain.
  ///
  /// It is refused as an answer for the same reason it exists: an installation named after it would
  /// be indistinguishable from an unstamped tree, and every stamp in this program keys on the
  /// literal.
  static const String placeholder = 'example.invalid';

  /// Whether [value] is a domain name this program will write anywhere.
  ///
  /// The one grammar every domain-shaped value of an installation is measured against — the branch
  /// name here, and the build plane, the unit apex and the platform domain in the cluster map. They
  /// are the same kind of thing, so a second grammar for the others would let one of them accept
  /// what the first refuses.
  ///
  /// Lower case, because these values are written into manifests that compare them literally, and
  /// at least two labels, because a single label is a machine name rather than a domain. An
  /// underscore is refused: it is legal in a git branch name and illegal in a host name, which is
  /// how a typo used to survive as far as the first failed lookup.
  static bool isFqdn(String value) => _fqdn.hasMatch(value);

  /// The checkout the branch is cut in.
  final String repository;

  /// What it is cut from.
  final String trunk;

  /// The branch this run cuts, named for the domain this installation answers on.
  ///
  /// An answer and not an argument: it is the one value nobody can put in a file that ships to
  /// every installation, and every step of this program that touches it reads the same one by name.
  static String branchIn(StepContext context) => context.answers.text('fqdn');

  @override
  Future<CheckResult> check(StepContext context) async {
    final String fqdn = branchIn(context);
    if (fqdn == placeholder) {
      return const CheckResult.blocked(
        '"$placeholder" is what the trunk carries instead of a domain, and an installation cannot '
        'be named after it — give the domain this installation is reached under',
      );
    }
    if (!isFqdn(fqdn)) {
      return CheckResult.blocked(
        '"$fqdn" is not a domain name, and it would become this installation\'s branch name, its '
        'cluster map and every host in its manifests — lower case labels of letters, digits and '
        'dashes, at least two of them',
      );
    }

    final String? head = await _head(context);
    if (head == null) {
      return CheckResult.blocked(
        'the checkout at $repository has no branch checked out, so there is nothing to cut from',
      );
    }
    if (head == fqdn) {
      return CheckResult.satisfied('$fqdn is checked out');
    }
    if (head != trunk) {
      return CheckResult.blocked(
        'this checkout is on "$head", and an installation is generated either from "$trunk" or in '
        'place on "$fqdn"',
      );
    }

    if (await _branchExists(context)) {
      return CheckResult.blocked(
        'a branch called $fqdn already exists here — check it out to stamp it again, or delete it '
        'if it is not the installation you mean; this refuses to reset a branch somebody made',
      );
    }

    final CommandResult dirty = await _status(context);
    if (!dirty.ok) {
      return CheckResult.blocked(
        'the state of the working tree could not be read: ${dirty.stderr.trim()}',
      );
    }
    if (dirty.trimmed.isNotEmpty) {
      return CheckResult.blocked(
        'the working tree is not clean, and a branch cut from it would carry changes nobody '
        'declared: ${dirty.trimmed.split('\n').join(', ')}',
      );
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['git', '-C', repository, 'checkout', '-b', branchIn(context)]);

  @override
  Future<void> apply(StepContext context) async {
    await _mustRun(context, <String>['-C', repository, 'checkout', '-b', branchIn(context)]);
  }

  @override
  Future<void> undo(StepContext context) async {
    // Only when this branch is what is checked out. An undo runs while cleaning up after a failure,
    // and deleting a branch that something else moved to would take away work nobody asked to lose.
    final String fqdn = branchIn(context);
    if (await _head(context) != fqdn) {
      return;
    }
    await _mustRun(context, <String>['-C', repository, 'checkout', trunk]);
    // The branch has not been pushed by anything in this program, so what is deleted here exists
    // only on this machine.
    await _mustRun(context, <String>['-C', repository, 'branch', '-D', fqdn]);
  }

  Future<void> _mustRun(StepContext context, List<String> argv) async {
    final CommandResult answer = await context.shell.run(Command('git', argv));
    if (!answer.ok) {
      throw CommandFailed(
        argv: <String>['git', ...argv],
        exitCode: answer.exitCode,
        stderr: answer.stderr,
      );
    }
  }

  /// The branch that is checked out, or null when there is none.
  ///
  /// A detached head answers with the word `HEAD`, which is not a branch and is not something to
  /// cut a branch from without saying so.
  Future<String?> _head(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD']),
    );
    if (!answer.ok || answer.trimmed.isEmpty || answer.trimmed == 'HEAD') {
      return null;
    }
    return answer.trimmed;
  }

  Future<bool> _branchExists(StepContext context) async {
    final CommandResult answer = await context.shell.run(
      Command.observing('git', <String>[
        '-C',
        repository,
        'rev-parse',
        '--verify',
        '--quiet',
        'refs/heads/${branchIn(context)}',
      ]),
    );
    return answer.ok;
  }

  Future<CommandResult> _status(StepContext context) => context.shell.run(
    Command.observing('git', <String>['-C', repository, 'status', '--porcelain']),
  );
}

/// Labels of letters, digits and dashes, joined by dots, at least two of them.
final RegExp _fqdn = RegExp(
  r'^(?=.{1,253}$)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)+$',
);
