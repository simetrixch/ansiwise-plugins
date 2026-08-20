import 'package:ansiwise_core/ansiwise_core.dart';

/// Publishes the value one key holds in one committed file of the branch this checkout stands on.
///
/// **What this is for.** Some values an operation needs are recorded in a file the branch itself
/// carries — recorded there by an earlier run, or by another program — and asking an operator for
/// one again invites an answer that disagrees with what stands written. This step reads the value
/// where it was recorded and publishes it as a measurement, so a later row takes it with
/// `{measured: value}` and no person ever re-types it.
///
/// **It reads the COMMITTED byte, never the working copy.** `git show HEAD:<path>` answers with what
/// the branch states, and that is the difference that matters: a working-tree edit in progress is
/// nobody's decision yet, and an operation acting on it would act on something no history carries.
///
/// **The path may name the branch without knowing it.** A file recorded per installation is very
/// often NAMED for the branch it stands on, and the branch is exactly what a program file shipping
/// to every installation cannot write. So the path may carry the slot `<branch>`, and this step
/// fills it with the branch this checkout stands on — a fact git answers, read here rather than
/// asked as one more question that could contradict the checkout.
///
/// **The two names come apart, and that is what the second slot is for.** The file the value stands
/// in is not always the one named for this checkout's own branch: a map kept for ANOTHER
/// installation is carried on this branch under that installation's name, and the checkout reading
/// it never stands on the branch it names. So the path may also carry the slot named by
/// `run_answer`, filled from that answer of the run — the same mechanism, under the same argument
/// name, that `copy_branch_file` fills its two paths with.
///
/// **What it reaches, said plainly, because the path argument looks more general than it is.** It
/// reaches one path inside the checkout at `repository`, as the branch that checkout stands on
/// COMMITS it, with `<branch>` and the one slot `run_answer` names filled. It reaches nothing else:
/// not the working copy, not a file only some other branch carries — check that branch out and the
/// step reads it there — not a path outside the checkout, and not a second axis, because one run
/// answer fills one slot and a path still carrying a slot after both are filled is refused rather
/// than guessed at.
///
/// **The file is read as a settings file: one `key: value` or `KEY=value` line per key.** That is
/// the one shape both notations this step meets have in common, and it is deliberately the whole of
/// the grammar — no nesting, no list, no expression. A value that needs more shape than one line is
/// not a value to hand a later row as one piece of text.
///
/// **A key that is absent, or holds nothing, is a refusal and never an empty publication.** The sink
/// refuses an empty value by contract, because "the file answered with nothing" and "nothing here
/// could be read" are different facts and the row that takes the value cannot tell them apart
/// afterwards. The refusal names the file and the key, which is what an operator can act on.
///
/// It only reads. Nothing on the machine changes, so a dry run performs it and the value is there
/// for the rows that follow.
final class MeasureValueInBranchFile extends ObservingStep {
  /// Publishes what [key] holds in [path] at the head of the checkout at [repository].
  const MeasureValueInBranchFile({
    required this.repository,
    required this.path,
    required this.key,
    this.runAnswer,
  });

  /// Builds the step from what the program gave it.
  factory MeasureValueInBranchFile.fromArguments(Arguments arguments) => MeasureValueInBranchFile(
    repository: arguments.text('repository'),
    path: arguments.text('path'),
    key: arguments.text('key'),
    runAnswer: arguments.optionalText('run_answer'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'repository',
      kind: ArgumentKind.text,
      describes: 'the checkout whose branch carries the file the value is recorded in',
    ),
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the file inside the checkout, as the branch tracks it. It may carry the slot <branch> '
          'where the name of the branch this checkout stands on belongs, because such a file is '
          'often named for its own branch and no program file can write that name, and the slot '
          'named by run_answer where that answer\'s value belongs',
    ),
    ArgumentSpec(
      name: 'key',
      kind: ArgumentKind.text,
      describes:
          'the key whose value is published, on a line of the shape "key: value" or "KEY=value"',
    ),
    ArgumentSpec(
      name: 'run_answer',
      kind: ArgumentKind.answerName,
      required: false,
      describes:
          'the name of the answer whose value fills the slot spelled with that same name in the '
          'path — write "fqdn" here and every "<fqdn>" in it is filled with this run\'s fqdn, '
          'which is how a file carrying ANOTHER installation\'s name is read off this branch. '
          'Leave it off where the path is named for its own branch alone',
    ),
  ];

  /// What this step publishes.
  static const List<MeasurementSpec> publishes = <MeasurementSpec>[
    MeasurementSpec(
      name: MeasurementName('value'),
      describes: 'the value the named key holds in the named file of this branch',
    ),
  ];

  /// The checkout whose branch carries the file.
  final String repository;

  /// The file inside the checkout, before any slot in it is filled.
  final String path;

  /// The key whose value is published.
  final String key;

  /// WHICH answer fills the slot spelled the same way in the path, or null where it carries none.
  final String? runAnswer;

  /// **Published HERE, in the check, and that is the shape a measuring step has.** The check runs in
  /// every mode, so a dry run holds the value the rows after this one read — and a step that only
  /// published while applying would leave a dry run planning against a measurement nobody made.
  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult head = await context.shell.run(
      Command.observing(
        'git',
        arguments: <String>['-C', repository, 'rev-parse', '--abbrev-ref', 'HEAD'],
      ),
    );
    if (!head.ok || head.trimmed.isEmpty || head.trimmed == 'HEAD') {
      return CheckResult.blocked(
        'the checkout at $repository has no branch checked out, and what is read here is what a '
        'branch states about itself',
      );
    }

    final String named = filledSlots(path, <String, String>{
      'branch': head.trimmed,
      ..._answerSlot(context),
    });
    if (leftoverSlotIn(named) case final String leftover) {
      return CheckResult.blocked(
        'the path "$path" still carries "$leftover" after filling <branch> and the run\'s own '
        'answer — the two slots this step fills — so the row names a file nothing can resolve',
      );
    }

    final CommandResult shown = await context.shell.run(
      Command.observing('git', arguments: <String>['-C', repository, 'show', 'HEAD:$named']),
    );
    if (!shown.ok) {
      return CheckResult.blocked(
        'the branch ${head.trimmed} carries no file at $named, and it is where this row says the '
        'value of "$key" is recorded: ${shown.stderr.trim()}',
      );
    }

    final String? value = _valueIn(shown.stdout);
    if (value == null || value.isEmpty) {
      return CheckResult.blocked(
        '$named on ${head.trimmed} records no value under "$key" — nothing has written it there '
        'yet, and publishing an absence as a value would hand the rows after this one an empty '
        'text they cannot tell from a real one',
      );
    }

    context.measurements.publish(const MeasurementName('value'), value);
    return CheckResult.satisfied('$named on ${head.trimmed} records $key: $value');
  }

  /// The one slot value the row's answer supplies, or nothing where it names none.
  Map<String, String> _answerSlot(StepContext context) {
    if (runAnswer case final String name) {
      if (context.answers.optionalText(name) case final String value) {
        return <String, String>{name: value};
      }
    }
    return const <String, String>{};
  }

  /// The value the first line carrying [key] holds, or null where no line does.
  ///
  /// One line per key is the whole grammar, so the first line that matches IS the value. Quotes a
  /// notation put around the value are taken off, because they are that notation's and not the
  /// value's.
  String? _valueIn(String content) {
    final RegExp line = RegExp('^[ \\t]*${RegExp.escape(key)}[ \\t]*[:=][ \\t]*(.*)\$');
    for (final String each in content.split('\n')) {
      final RegExpMatch? match = line.firstMatch(each.trimRight());
      if (match == null) {
        continue;
      }
      String value = match.group(1)!.trim();
      if (value.length >= 2 &&
          (value.startsWith('"') && value.endsWith('"') ||
              value.startsWith("'") && value.endsWith("'"))) {
        value = value.substring(1, value.length - 1);
      }
      return value;
    }
    return null;
  }
}
