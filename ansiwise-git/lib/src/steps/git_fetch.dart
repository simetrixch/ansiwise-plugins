import 'package:ansiwise_core/ansiwise_core.dart';

/// Brings one ref of one remote into this checkout, so a name means what the remote publishes.
///
/// **WHAT THIS EXISTS TO END.** A checkout resolves `origin/master` to whatever it last saw, and a
/// tag it has never fetched to nothing at all. Both are silent: a step that tags `origin/master`
/// puts a release on a tree nobody published, and a step that merges a tag refuses with a message
/// about a name — and in each case the checkout was simply behind. Neither is something a program
/// could state as a precondition, because a precondition nobody can check is the shape this package
/// keeps finding and removing.
///
/// **ONE REF PER ROW, and the row says which kind.** A branch and a tag are different statements —
/// "the branch has moved and this checkout should follow" against "this name exists and this
/// checkout should hold it" — and a row that made both at once would be satisfied by half of it. A
/// program needing both writes two rows, and each says what it is for.
///
/// **What is compared is what the REMOTE publishes, not when the last fetch was.** A checkout that
/// fetched a second ago and one that fetched last week are the same checkout if the ref has not
/// moved, so a second run has nothing to do — which is what makes this a step rather than a command
/// somebody remembers to type.
///
/// It changes refs and nothing in the working tree. That is still a change, so a run that only says
/// what would change does not perform it: what it announces is the ref it would bring, and from
/// where.
final class GitFetch extends IrreversibleStep {
  /// Brings [branch] or [tag] — the latter also nameable through [tagAnswer] — of [remote] into
  /// the checkout this row names.
  const GitFetch({
    required this.remote,
    this.repository,
    this.repositoryAnswer,
    this.branch,
    this.tag,
    this.tagAnswer,
  });

  /// Builds the step from what the program gave it.
  factory GitFetch.fromArguments(Arguments arguments) => GitFetch(
    repository: arguments.optionalText('repository'),
    repositoryAnswer: arguments.optionalText('repository_answer'),
    remote: arguments.optionalText('remote') ?? 'origin',
    branch: arguments.optionalText('branch'),
    tag: arguments.optionalText('tag'),
    tagAnswer: arguments.optionalText('tag_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the checkout brought up to date, where the path is the program\'s to know',
    ),
    ArgumentSpec(
      name: 'repository_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer holding that path, where it is the running machine\'s to know',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: 'origin',
      describes: 'the remote asked what it publishes',
    ),
    ArgumentSpec(
      name: 'branch',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the branch whose remote-tracking ref is brought level with what the remote publishes — '
          'write this where a later row resolves "<remote>/<branch>" and must mean the published '
          'tree rather than the last one this checkout happened to see',
    ),
    // READ AS OPTIONAL EVEN WHERE A ROW ALWAYS STATES IT: a row taking the name from a measurement
    // has no value to give while a program is being examined, and a required read would refuse the
    // program rather than the run.
    ArgumentSpec(
      name: 'tag',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the tag brought into this checkout — write this where a later row resolves a tag by '
          'name, which a checkout that has never fetched it resolves to nothing at all',
    ),
    ArgumentSpec(
      name: 'tag_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer this run reads the tag out of, where a person names it — a row '
          'writes "tag" or this, never both',
    ),
  ];

  /// The checkout, where the program knows the path.
  final String? repository;

  /// The name of the answer holding it, where the run knows the path.
  final String? repositoryAnswer;

  /// The remote asked what it publishes.
  final String remote;

  /// The branch this row brings level, or null where it names a tag instead.
  final String? branch;

  /// The tag this row brings in, or null where it names a branch instead.
  final String? tag;

  /// The name of the answer the tag is read out of, or null where the row writes it as [tag].
  final String? tagAnswer;

  /// Why the change this step makes cannot be taken back.
  @override
  String get irreversibleReason =>
      'a ref this checkout is moved onto is a position it stood on nowhere else: what it pointed at '
      'before is kept in no other name, so putting it back would mean knowing a commit nothing '
      'recorded';

  @override
  Future<CheckResult> check(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    final ({String commit, String? refusal}) published = await _published(context);
    if (published.refusal case final String refusal) {
      return CheckResult.blocked(
        '$remote could not be asked what it publishes, so nothing here says whether it carries a '
        '${branch != null ? 'branch' : 'tag'} called "${branch ?? _tagOf(context)}": $refusal',
      );
    }
    if (published.commit.isEmpty) {
      return CheckResult.blocked(
        '$remote publishes no ${branch != null ? 'branch' : 'tag'} called '
        '"${branch ?? _tagOf(context)}", so there is nothing to bring — the name is wrong, or '
        'whatever writes it has not run',
      );
    }
    return await _here(context) == published.commit
        ? CheckResult.satisfied(
            '${branch ?? _tagOf(context)} is here on ${published.commit}, as $remote publishes it',
          )
        : const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.argv(<String>['git', '-C', _repositoryOf(context), ..._fetch(context)]);
  }

  @override
  Future<void> apply(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      throw StateError(refusal);
    }
    final Command fetching = Command.detailed(
      'git',
      arguments: <String>['-C', _repositoryOf(context), ..._fetch(context)],
    );
    final CommandResult fetched = await context.shell.run(fetching);
    if (!fetched.ok) {
      throw CommandFailed(
        argv: fetching.argv,
        exitCode: fetched.exitCode,
        stdout: '',
        stderr: fetched.stderr,
      );
    }
  }

  /// What the fetch command is, for the one kind of ref this row names.
  ///
  /// The branch form names its destination outright rather than relying on what the checkout's
  /// configuration happens to map: a remote added by hand often maps nothing, and the fetch then
  /// updates a name no later row reads.
  List<String> _fetch(StepContext context) {
    final String? named = branch;
    if (named != null) {
      return <String>['fetch', remote, '+refs/heads/$named:refs/remotes/$remote/$named'];
    }
    return <String>['fetch', remote, 'tag', _tagOf(context)];
  }

  /// What this checkout currently resolves the row's ref to, or the empty text where it holds none.
  Future<String> _here(StepContext context) async {
    final String? named = branch;
    final String what = named != null
        ? 'refs/remotes/$remote/$named'
        : 'refs/tags/${_tagOf(context)}';
    final CommandResult resolved = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          _repositoryOf(context),
          'rev-parse',
          '--quiet',
          '--verify',
          '$what^{commit}',
        ],
      ),
    );
    return resolved.ok ? resolved.trimmed : '';
  }

  /// The commit the remote publishes the row's ref on, the empty text where it publishes none, or
  /// why neither could be read.
  ///
  /// **AN EMPTY ANSWER IS AN ANSWER AND A NON-ZERO EXIT IS NOT.** `ls-remote` writes nothing at exit
  /// zero for a name the remote does not publish, so the empty answer keeps meaning that. A non-zero
  /// exit is the remote not having been reached at all — no credential, no network, a host key it
  /// would not accept — and folded into the same empty text it produced a verdict ABOUT THE REMOTE,
  /// "$remote publishes no branch called X — the name is wrong, or whatever writes it has not run",
  /// out of a question nobody managed to put to it.
  ///
  /// **THE PATTERN CARRIES A STAR FOR A TAG, and that is not decoration.** An annotated tag is an
  /// object of its own, and a remote answers with both its id and the commit it dereferences to —
  /// but only where the pattern matches the peeled ref as well. Asked for the exact name it answers
  /// with the object id alone, and comparing that against a commit reports a difference on every
  /// run, for ever. A lightweight tag has no dereferenced line anywhere, and there the one id IS the
  /// commit.
  Future<({String commit, String? refusal})> _published(StepContext context) async {
    final CommandResult listed = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>[
          '-C',
          _repositoryOf(context),
          'ls-remote',
          remote,
          branch != null ? 'refs/heads/$branch' : 'refs/tags/${_tagOf(context)}*',
        ],
      ),
    );
    if (!listed.ok) {
      return (
        commit: '',
        refusal:
            'git exited ${listed.exitCode}'
            '${listed.stderr.trim().isEmpty ? ' and wrote nothing' : ': ${listed.stderr.trim()}'}',
      );
    }
    final String wanted = branch != null ? 'refs/heads/$branch' : 'refs/tags/${_tagOf(context)}';
    String plain = '';
    for (final String line in listed.trimmed.split('\n')) {
      final List<String> parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 2) {
        continue;
      }
      if (parts[1] == '$wanted^{}') {
        return (commit: parts[0], refusal: null);
      }
      if (parts[1] == wanted) {
        plain = parts[0];
      }
    }
    return (commit: plain, refusal: null);
  }

  /// The checkout this row points at, or the empty text where it points at none.
  String _repositoryOf(StepContext context) {
    if (repository case final String written) {
      return written;
    }
    if (repositoryAnswer case final String named) {
      return context.answers.has(named) ? context.answers.text(named).trim() : '';
    }
    return '';
  }

  /// Why this row cannot be read at all, or null where it can.
  String? _unreadable(StepContext context) {
    if (repository != null && repositoryAnswer != null) {
      return 'this row states the checkout as text AND names an answer holding it, and one row '
          'points at one checkout';
    }
    if (repository == null && repositoryAnswer == null) {
      return 'this row states no checkout: it writes the path, or it names the answer holding it';
    }
    if (_repositoryOf(context).isEmpty) {
      return 'this run holds no answer called "$repositoryAnswer", and that is where this row says '
          'the checkout is named';
    }
    final bool named = branch != null && branch!.isNotEmpty;
    final bool written = tag != null && tag!.isNotEmpty;
    if (written && tagAnswer != null) {
      return 'this row states "tag" AND names "tag_answer", and one row brings one tag — write '
          'the tag, or name the answer holding it, never both';
    }
    final bool tagged = written || tagAnswer != null;
    if (named && tagged) {
      return 'this row names a branch AND a tag, and they are different statements — a row saying '
          'both would be satisfied by half of it. Write two rows, each saying what it is for';
    }
    if (!named && !tagged) {
      return 'this row names neither a branch nor a tag, so there is nothing to bring — it writes '
          '"branch" or "tag", or names "tag_answer" where a person answers the tag. Where the '
          'name comes from a measurement, the row publishing it has still to pass';
    }
    if (!named && _tagOf(context).isEmpty) {
      return 'this run holds no answer called "$tagAnswer", and that is where this row says the '
          'tag is named';
    }
    return null;
  }

  /// The tag this row brings in, or the empty text while nothing names one.
  String _tagOf(StepContext context) {
    if (tag case final String written when written.isNotEmpty) {
      return written;
    }
    if (tagAnswer case final String named) {
      return context.answers.has(named) ? context.answers.text(named).trim() : '';
    }
    return '';
  }
}
