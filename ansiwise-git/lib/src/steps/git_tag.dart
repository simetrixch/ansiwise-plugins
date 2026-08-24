import 'package:ansiwise_core/ansiwise_core.dart';

/// Puts one annotated tag on one commit and pushes it, and takes it back off on an undo.
///
/// **A TAG THAT MOVES IS A LIE, and this step refuses to tell it.** What a tag is for is to say
/// which tree something was cut from — everything downstream regenerates from exactly that. A tag
/// re-pointed at another commit leaves every statement made about it standing while the thing it
/// names has changed, and nothing anywhere reports that. So a tag of this name already on another
/// commit is REFUSED rather than moved, and an operator who really means to move it does it
/// themselves, deliberately, outside a program.
///
/// **The local side and the remote side are one postcondition.** A tag that exists here and not
/// there is a release nobody else can resolve, and one that exists there and not here is a repeat
/// run with nothing to do. Both are asked, and the step is finished only when both carry the name
/// on the same commit.
///
/// **What the name MEANS is never this package's business.** A tag is text git accepts; whether it
/// follows a product's release grammar is that product's question, asked by whatever composed the
/// text before this row runs. Git itself is asked whether it would take the name, rather than a
/// second grammar being written here that agrees with git on the day it is written and drifts from
/// then on.
final class GitTag extends ReversibleStep<bool> {
  /// Puts [tag] on what [ref] resolves to, in the checkout at [repository], and pushes it to
  /// [remote].
  const GitTag({
    required this.tag,
    required this.ref,
    required this.message,
    this.repository,
    this.repositoryAnswer,
    this.remote = 'origin',
  });

  /// Builds the step from what the program gave it.
  factory GitTag.fromArguments(Arguments arguments) => GitTag(
    repository: arguments.optionalText('repository'),
    repositoryAnswer: arguments.optionalText('repository_answer'),
    tag: arguments.optionalText('tag') ?? '',
    ref: arguments.text('ref'),
    message: arguments.text('message'),
    remote: arguments.optionalText('remote') ?? 'origin',
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    // ONE OF THE TWO, and the row says which. A checkout on a machine this program installs stands
    // at a path the program knows and writes here. A checkout on the workstation somebody cuts a
    // release from stands wherever that person keeps it, which is a fact of that workstation and of
    // nothing else — so the row names the ANSWER instead, and the path never reaches a file that
    // ships to everybody.
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      required: false,
      describes: "the checkout the tag is put in, where the path is the program's to know",
    ),
    ArgumentSpec(
      name: 'repository_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          "the name of the answer holding that path, where it is the running machine's to know",
    ),
    // READ AS AN OPTIONAL ONE, and it is not optional. Everything that examines a program before it
    // runs has to build the step, and a row taking this from a measurement has no value to give it
    // yet — so a required read would refuse the program itself rather than the run. The check below
    // refuses an empty one, which is where the demand actually belongs.
    ArgumentSpec(
      name: 'tag',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'the tag, as text git accepts. Whether it follows a product\'s release grammar is that '
          'product\'s question, asked by whatever composed the text — this step asks git and '
          'nothing else',
    ),
    ArgumentSpec(
      name: 'ref',
      kind: ArgumentKind.text,
      describes:
          'what the tag points at, as anything git resolves to a commit — the tag is what '
          'everything downstream regenerates from, so this is the whole statement it makes',
    ),
    ArgumentSpec(
      name: 'message',
      kind: ArgumentKind.text,
      describes:
          'the annotation. An annotated tag carries who made it and when, and a lightweight one '
          'carries neither — so what a release was cut by would be unanswerable afterwards',
    ),
    ArgumentSpec(
      name: 'remote',
      kind: ArgumentKind.text,
      required: false,
      defaultValue: 'origin',
      describes: 'the remote the tag is pushed to, so that anything else can resolve it',
    ),
  ];

  /// The checkout the tag is put in, where the program knows the path.
  final String? repository;

  /// The name of the answer holding it, where the run knows the path.
  final String? repositoryAnswer;

  /// The tag.
  final String tag;

  /// What it points at.
  final String ref;

  /// The annotation.
  final String message;

  /// The remote it is pushed to.
  final String remote;

  /// The checkout this row points at, or the empty text where the row points at none.
  ///
  /// Resolved in ONE place because six commands name it: a row stating both sources, or neither, is
  /// a row nobody can read, and finding that out separately in each of them is how two of them come
  /// to disagree.
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
    return null;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      return CheckResult.blocked(refusal);
    }
    if (tag.isEmpty) {
      return const CheckResult.blocked(
        'this row states no tag: the row before it publishes one and this row takes it from there, '
        'so a run reaching here with nothing has that row still to pass',
      );
    }
    final String repository = _repositoryOf(context);
    final CommandResult legal = await context.shell.run(
      Command.observing('git', arguments: <String>['check-ref-format', 'refs/tags/$tag']),
    );
    if (!legal.ok) {
      return CheckResult.blocked('git refuses "$tag" as a tag name: ${legal.stderr.trim()}');
    }
    final String? wanted = await _commitOf(context, ref);
    if (wanted == null) {
      return CheckResult.blocked(
        '$ref resolves to no commit in the checkout at $repository, so there is nothing to tag',
      );
    }
    final String? here = await _commitOf(context, 'refs/tags/$tag');
    if (here != null && here != wanted) {
      return CheckResult.blocked(
        '$tag is already on $here in this checkout and $ref is $wanted. A tag that moves leaves '
        'every statement made about it standing while the tree it names has changed, so this step '
        'refuses to move one',
      );
    }
    final String? there = await _onRemote(context);
    if (there != null && there != wanted) {
      return CheckResult.blocked(
        '$remote already carries $tag on $there and $ref is $wanted — the same refusal as above, '
        'and worse: something has already resolved that tag',
      );
    }
    if (here == wanted && there == wanted) {
      return CheckResult.satisfied('$tag is on $wanted here and on $remote');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      return StepPlan.nothing(refusal);
    }
    return StepPlan.argv(<String>[
      'git',
      '-C',
      _repositoryOf(context),
      'push',
      remote,
      'refs/tags/$tag',
    ]);
  }

  @override
  Future<void> apply(StepContext context) async {
    if (_unreadable(context) case final String refusal) {
      throw StateError(refusal);
    }
    final String repository = _repositoryOf(context);
    if (await _commitOf(context, 'refs/tags/$tag') == null) {
      final Command tagging = Command.detailed(
        'git',
        arguments: <String>['-C', repository, 'tag', '--annotate', tag, '--message', message, ref],
      );
      final CommandResult tagged = await context.shell.run(tagging);
      if (!tagged.ok) {
        throw CommandFailed(
          argv: tagging.argv,
          exitCode: tagged.exitCode,
          stdout: '',
          stderr: tagged.stderr,
        );
      }
    }
    // PUSHED EVERY TIME THE REMOTE LACKS IT, including when this run did not create the tag. A tag
    // made by an interrupted earlier run stands here and nowhere else, and a step that only pushed
    // what it had just created would leave that one local for ever.
    final Command pushing = Command.detailed(
      'git',
      arguments: <String>['-C', repository, 'push', remote, 'refs/tags/$tag'],
    );
    final CommandResult pushed = await context.shell.run(pushing);
    if (!pushed.ok) {
      throw CommandFailed(
        argv: pushing.argv,
        exitCode: pushed.exitCode,
        stdout: '',
        stderr: pushed.stderr,
      );
    }
  }

  /// Whether the tag was already there before this ran, here or on the remote.
  ///
  /// A tag somebody else pushed is not this run's to delete: something may already have resolved it,
  /// and taking it away would break whatever did.
  @override
  Future<bool> capture(StepContext context) async =>
      _unreadable(context) != null ||
      await _commitOf(context, 'refs/tags/$tag') != null ||
      await _onRemote(context) != null;

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    final String repository = _repositoryOf(context);
    await context.shell.run(
      Command.detailed(
        'git',
        arguments: <String>['-C', repository, 'push', '--delete', remote, tag],
      ),
    );
    await context.shell.run(
      Command.detailed('git', arguments: <String>['-C', repository, 'tag', '--delete', tag]),
    );
  }

  /// The commit [what] resolves to in this checkout, or null where it resolves to nothing.
  Future<String?> _commitOf(StepContext context, String what) async {
    final String repository = _repositoryOf(context);
    final CommandResult resolved = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--quiet', '--verify', '$what^{commit}'],
      ),
    );
    final String text = resolved.trimmed;
    return resolved.ok && text.isNotEmpty ? text : null;
  }

  /// The commit the remote carries this tag on, or null where it carries none.
  ///
  /// **THE DEREFERENCED LINE IS THE ONE THAT COUNTS.** An annotated tag is an object of its own, so
  /// the remote answers twice: once with the tag object's own id and once with `^{}` and the commit
  /// it points at. Reading the first would compare a tag object against a commit, which never match,
  /// and every run would report a tag that has moved.
  Future<String?> _onRemote(StepContext context) async {
    final String repository = _repositoryOf(context);
    final CommandResult listed = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'ls-remote', '--tags', remote, 'refs/tags/$tag'],
      ),
    );
    if (!listed.ok) {
      return null;
    }
    String? plain;
    for (final String line in listed.trimmed.split('\n')) {
      final List<String> parts = line.trim().split(RegExp(r'\s+'));
      if (parts.length != 2) {
        continue;
      }
      if (parts[1] == 'refs/tags/$tag^{}') {
        return parts[0];
      }
      if (parts[1] == 'refs/tags/$tag') {
        plain = parts[0];
      }
    }
    return plain;
  }
}
