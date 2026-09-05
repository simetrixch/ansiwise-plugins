import 'package:ansiwise_core/ansiwise_core.dart';

/// Writes one committed file of the branch this checkout stands on to a destination this row names.
///
/// **What this is for.** An operation that generates one installation from another needs a handful
/// of files the first installation already carries — rendered, filled in, decided. Rendering them a
/// second time would need every value they were rendered from, which is exactly the set of questions
/// the operation exists to NOT ask again; copying the file carries the decisions without re-deciding
/// any of them. What the destination then still needs changed is the business of the rows after this
/// one, each naming its own difference.
///
/// **The COMMITTED byte is copied, never the working copy.** `git show HEAD:<path>` answers with
/// what the branch states, so an edit in progress in the source checkout — somebody's half-finished
/// work, or debris of a failed run — cannot travel into a file another branch will commit.
///
/// **Two slots, because the two names come from two different places.** The source path may carry
/// `<branch>`, filled with the branch the SOURCE checkout stands on — a file recorded per
/// installation is often named for its own branch, and no program file can write that name. Both
/// paths may carry the slot named by `run_answer`, filled from that answer of the run — a file kept
/// per stage is the shape this exists for, and it is the same mechanism every template writer in
/// this framework uses under the same argument name.
///
/// **The destination is a plain file on the machine, and that is the whole claim.** It may stand
/// inside another checkout's working tree, where a later row commits it, or outside every checkout,
/// where later rows only read it. This step neither stages nor commits anything: what a branch
/// records is the business of the row that commits, and a copy that also staged would make this one
/// step two acts with one undo.
final class CopyBranchFile extends ReversibleStep<String?> {
  /// The source checkout is often prepared — cloned, fetched, checked out — by earlier rows of the
  /// same program, so before those have run there may be nothing here to read. In the two modes that
  /// change nothing that is the normal state, and the record marks the row declared rather than
  /// counting the refusal against the run.
  @override
  bool get restsOnAnEarlierStep => true;

  /// Copies [path] at the head of [repository] to [destination].
  const CopyBranchFile({
    required this.repository,
    required this.path,
    required this.destination,
    required this.fileMode,
    this.runAnswer,
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory CopyBranchFile.fromArguments(Arguments arguments) => CopyBranchFile(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    destination: arguments.text('destination'),
    fileMode: arguments.integer('file_mode'),
    runAnswer: arguments.optionalText('run_answer'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose branch carries the file that is copied',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the file inside that checkout, as the branch tracks it. It may carry the slot <branch> '
          'where the name of the branch the source checkout stands on belongs, and the slot named '
          'by run_answer where that answer\'s value belongs',
    ),
    ArgumentSpec(
      name: 'destination',
      kind: ArgumentKind.text,
      describes:
          'where the copy goes on this machine — inside another checkout\'s working tree where a '
          'later row commits it, or outside every checkout where later rows only read it. It may '
          'carry the slot named by run_answer',
    ),
    ArgumentSpec(
      name: 'file_mode',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 0,
        most: 4095,
        because:
            'a permission mode is twelve bits, so 4095 is 0o7777 and nothing outside it is a mode',
      ),
      describes:
          'the permissions the copy is written with, as the number the machine stores — 420 is the '
          'mode of a file anyone on the machine may read, 384 of one only its owner may',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'source path and the destination — write "stage" here and every "<stage>" in either is '
          'filled with this run\'s stage. Leave it off where neither carries such an axis',
    ),
    elevationArgument,
  ];

  /// The checkout whose branch carries the file.
  final String repository;

  /// The file inside the source checkout, before any slot in it is filled.
  final String path;

  /// Where the copy goes, before any slot in it is filled.
  final String destination;

  /// The permissions the copy is written with.
  final int fileMode;

  /// WHICH answer fills the slot spelled the same way in both paths, or null where they carry none.
  final String? runAnswer;

  /// Whether what this row points at belongs to root, so every read and write of it is elevated.
  ///
  /// ONE answer covering both paths, because both are reached and either can be root's: the source
  /// checkout, which git is asked for the committed byte, and the destination, which the files port
  /// reads and writes. A step that asked git as the operator and wrote as root would get an answer
  /// that is not the one it waits for — git reports a checkout it may not read as a branch that
  /// carries no such file, and the copy would be blocked for a reason about the file rather than
  /// about the account.
  final bool elevated;

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? source = await _source(context);
    return switch (source) {
      null => CheckResult.blocked(await _whyUnreadable(context)),
      _ =>
        await _destinationHolds(context, source)
            ? CheckResult.satisfied('${await _destinationFor(context)} already holds this file')
            : const CheckResult.ready(),
    };
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String? source = await _source(context);
    if (source == null) {
      return StepPlan.nothing(await _whyUnreadable(context));
    }
    final String to = await _destinationFor(context);
    final String current = await context.files.exists(to, elevated: elevated)
        ? await context.files.read(to, elevated: elevated)
        : '';
    return StepPlan.diff(to, before: current, after: source);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String? source = await _source(context);
    if (source == null) {
      // The engine applies a step only after its check answered ready, and that check refuses this
      // by name — so reaching here is a call out of order, and writing anyway would put an empty
      // file where the row promised a copy.
      throw StateError(await _whyUnreadable(context));
    }
    await context.files.write(
      await _destinationFor(context),
      source,
      mode: fileMode,
      elevated: elevated,
    );
  }

  /// What the destination held before, or null when it was not there.
  @override
  Future<String?> capture(StepContext context) async {
    final String to = await _destinationFor(context);
    return await context.files.exists(to, elevated: elevated)
        ? context.files.read(to, elevated: elevated)
        : null;
  }

  @override
  Future<void> undo(StepContext context, String? captured) async {
    final String to = await _destinationFor(context);
    if (captured == null) {
      // There was no file, so taking this back means the path is gone again. Returning here would
      // leave the copy standing while the record says the step was taken back.
      await context.files.delete(to, elevated: elevated);
      return;
    }
    await context.files.write(to, captured, mode: fileMode, elevated: elevated);
  }

  /// The committed text of the source file, or null where nothing here can be read.
  Future<String?> _source(StepContext context) async {
    final String? named = await _sourceFor(context);
    if (named == null) {
      return null;
    }
    final CommandResult shown = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'show', 'HEAD:$named'],
        elevated: elevated,
      ),
    );
    return shown.ok ? shown.stdout : null;
  }

  /// Why the source cannot be read, said once so the check, the plan and a call out of order all
  /// name the same thing.
  Future<String> _whyUnreadable(StepContext context) async {
    final String? branch = await _branch(context);
    if (branch == null) {
      return 'the checkout at $repository has no branch checked out, and what is copied is what a '
          'branch states';
    }
    final String? named = await _sourceFor(context);
    if (named == null) {
      // WHICH SLOTS WERE ACTUALLY FILLED, not which ones this step can fill. A row naming no
      // `run_answer` filled one, and telling its operator that two were filled sends them looking
      // for a second slot their row does not have.
      final String filled = runAnswer == null
          ? '<branch>, the one slot this row fills'
          : '<branch> and <$runAnswer>';
      return 'the path "$path" still carries a slot after filling $filled, so the row names a file '
          'nothing can resolve';
    }
    return 'the branch $branch carries no file at $named, and it is what this row copies';
  }

  /// The source path with its slots filled, or null while one is left over.
  Future<String?> _sourceFor(StepContext context) async {
    final String? branch = await _branch(context);
    if (branch == null) {
      return null;
    }
    final String named = filledSlots(path, <String, String>{
      'branch': branch,
      ..._answerSlot(context),
    });
    return leftoverSlotIn(named) == null ? named : null;
  }

  /// The destination with the run's own slot filled.
  Future<String> _destinationFor(StepContext context) async =>
      filledSlots(destination, _answerSlot(context));

  /// The one slot value the row's answer supplies, or nothing where it names none.
  Map<String, String> _answerSlot(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return <String, String>{name: value};
      }
    }
    return const <String, String>{};
  }

  /// Whether the destination already holds the source byte for byte.
  Future<bool> _destinationHolds(StepContext context, String source) async {
    final String to = await _destinationFor(context);
    if (!await context.files.exists(to, elevated: elevated)) {
      return false;
    }
    return await context.files.read(to, elevated: elevated) == source;
  }

  /// The branch the source checkout stands on, or null where there is none.
  Future<String?> _branch(StepContext context) async {
    final CommandResult head = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
        elevated: elevated,
      ),
    );
    if (!head.ok || head.trimmed.isEmpty || head.trimmed == 'HEAD') {
      return null;
    }
    return head.trimmed;
  }
}
