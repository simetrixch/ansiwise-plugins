import 'package:ansiwise_core/ansiwise_core.dart';

/// Whether a remote publishes the branch this run names.
///
/// ONE condition, pointed at a checkout and a remote by the installation that uses it, and
/// registered under whatever name that installation chose. What it reads is git's own answer to
/// `ls-remote`: does this remote carry `refs/heads/<branch>`. Which checkout, which remote and
/// which answer holds the branch name are properties of one product, so they arrive as values on
/// the installation's own configuration and are named nowhere here.
///
/// **THE BRANCH NAME IS AN ANSWER, and the configuration says which one.** A branch that is cut per
/// run is named for something only that run knows, so the name cannot stand in a file that ships to
/// every machine. What stands there is the NAME OF THE ANSWER, and the reading happens here — the
/// same arrangement `git_branch` uses, and deliberately the same argument name, so one installation
/// writes one word in the condition and in every branch row gated on it.
///
/// **TWO REGISTERED NAMES OVER ONE READING, and a program row still writes one bare word.** A
/// program acts both ways on this: where the remote already publishes the branch, the checkout is
/// stood on it and today's source branch merged in; where it does not, the branch is cut. Written as
/// `not: [remote_has_branch]` the second would be an operator behind `when:`, and an operator is
/// where a program file starts being a language. So there are two shapes,
/// [RemoteHasBranch.carrying] and [RemoteHasBranch.lacking], bound under two names.
///
/// **A REMOTE THAT COULD NOT BE ASKED IS REFUSED, NOT ANSWERED "IT DOES NOT PUBLISH IT".** An empty
/// answer at exit zero is git saying the remote carries no such branch. A non-zero exit is the
/// remote not having been reached at all — no credential, no network, a host key it would not
/// accept — and folding that into "it does not publish it" would cut a branch on top of one that is
/// already there, which is exactly the state a push refuses as a non-fast-forward. The refusal is
/// [ConditionUnanswerable], and it names the remote, the branch and what git said.
///
/// A run holding no answer under the name the configuration points at is refused the same way: the
/// condition was pointed at a name nothing answers, and both directions would be a claim about a
/// branch nobody named.
final class RemoteHasBranch implements Predicate {
  /// Asks whether [remote] publishes the branch this run answered under [nameAnswer], as seen from
  /// the checkout at [repository].
  ///
  /// [holdsWhenPublished] is which of the two registered shapes this is. It is not configuration and
  /// it never appears in a file: it is decided by which of the two names the installation bound.
  const RemoteHasBranch({
    required this.repository,
    required this.remote,
    required this.nameAnswer,
    this.holdsWhenPublished = true,
  });

  /// The shape that holds where the remote publishes the branch.
  factory RemoteHasBranch.carrying(Arguments values) =>
      RemoteHasBranch._from(values, holdsWhenPublished: true);

  /// The shape that holds where it does not.
  factory RemoteHasBranch.lacking(Arguments values) =>
      RemoteHasBranch._from(values, holdsWhenPublished: false);

  /// Builds either shape from what one installation told it.
  factory RemoteHasBranch._from(Arguments values, {required bool holdsWhenPublished}) =>
      RemoteHasBranch(
        repository: values.text('repository'),
        remote: values.optionalText('remote') ?? 'origin',
        nameAnswer: values.text('name_answer'),
        holdsWhenPublished: holdsWhenPublished,
      );

  /// What this condition has to be told before a program row may name it.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes:
          'the checkout the remote is asked from, as a path on the machine. Any checkout that '
          'knows the remote answers the same thing, so this is where the credential and the '
          'address are read from rather than a fact about the branch',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: 'origin',
      describes: 'the remote asked what it publishes',
    ),
    ArgumentSpec(
      name: 'name_answer',
      kind: ArgumentKind.answerName,
      describes:
          'the name of the answer this run reads the branch name out of — write "fqdn" here and '
          'the condition asks about whatever this run answered for "fqdn". The same word the '
          'branch rows gated on this condition write, so one installation names it once',
    ),
  ];

  /// The checkout the remote is asked from.
  final String repository;

  /// The remote asked what it publishes.
  final String remote;

  /// The name of the answer the branch name is read out of.
  final String nameAnswer;

  /// Which way this shape holds: true for the shape bound as `remote_has_branch`, false for the one
  /// bound as `remote_lacks_branch`.
  final bool holdsWhenPublished;

  @override
  Future<PredicateResult> evaluate(PredicateContext context) async {
    if (!context.answers.has(nameAnswer)) {
      throw ConditionUnanswerable(
        'this run holds no answer called "$nameAnswer", and that is where this condition was told '
        'the branch name comes from\n'
        'the installation configuration points this condition at that name, so the program has to '
        'declare it before the run starts',
      );
    }
    final String branch = context.answers.text(nameAnswer);
    final CommandResult listed = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'ls-remote', '--heads', remote, 'refs/heads/$branch'],
      ),
    );
    if (!listed.ok) {
      throw ConditionUnanswerable(
        '$remote could not be asked whether it publishes "$branch", so nothing here says whether '
        'it does: git exited ${listed.exitCode}'
        '${listed.stderr.trim().isEmpty ? ' and wrote nothing' : ': ${listed.stderr.trim()}'}\n'
        'answering that it does not would cut a branch on top of one that is already published, '
        'and the push at the end of that is refused as a non-fast-forward',
      );
    }

    final bool published = _carries(listed.trimmed, branch);
    // The reading is one reading; which shape this is decides only which way it holds. The sentence
    // says what the remote said, so a record reads the same either way.
    return published == holdsWhenPublished
        ? PredicateResult.holds(
            published
                ? '$remote publishes refs/heads/$branch'
                : '$remote publishes no branch called $branch',
          )
        : PredicateResult.doesNotHold(
            published
                ? '$remote publishes refs/heads/$branch'
                : '$remote publishes no branch called $branch',
          );
  }

  /// Whether [answer] names `refs/heads/[branch]` exactly.
  ///
  /// The pattern given to `ls-remote` matches the tail of a ref, so a remote carrying a longer name
  /// ending in this one would answer a line about it. The full name is compared here rather than the
  /// answer being read as a yes because it is not empty.
  bool _carries(String answer, String branch) {
    for (final String line in answer.split('\n')) {
      final List<String> parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length == 2 && parts[1] == 'refs/heads/$branch') {
        return true;
      }
    }
    return false;
  }
}
