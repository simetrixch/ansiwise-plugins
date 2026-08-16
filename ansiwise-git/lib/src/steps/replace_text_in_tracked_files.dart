import 'package:ansiwise_api/ansiwise_api.dart';

/// Replaces a placeholder in git-tracked files with an answer of the run.
///
/// **The set of files is FOUND, not named.** A content search over the tracked files answers with
/// the few that can possibly be in it, and git is what puts them back: an undo restores exactly the
/// paths this run rewrote and no other.
///
/// **Only the literal is replaced.** The step uses `git grep` and `sed`.
final class ReplaceTextInTrackedFiles extends ReversibleStep<List<String>> {
  /// Replaces [placeholder] with the value of the answer named [valueAnswer] in [tree].
  const ReplaceTextInTrackedFiles({
    required this.placeholder,
    required this.valueAnswer,
    this.tree,
    this.replacementFormat,
  });

  /// Builds the step from what the program gave it.
  factory ReplaceTextInTrackedFiles.fromArguments(Arguments arguments) => ReplaceTextInTrackedFiles(
    placeholder: arguments.text('placeholder'),
    valueAnswer: arguments.text('value_answer'),
    tree: arguments.optionalText('tree'),
    replacementFormat: arguments.optionalText('replacement_format'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'placeholder',
      kind: ArgumentKind.text,
      describes: 'the literal text standing in the files, which is matched exactly',
    ),
    ArgumentSpec(
      name: 'value_answer',
      kind: ArgumentKind.text,
      describes: 'the NAME of the answer this run holds, whose value replaces the placeholder',
    ),
    ArgumentSpec(
      name: 'tree',
      kind: ArgumentKind.text,
      required: false,
      describes: 'the path to restrict the search to, or empty for the whole checkout',
    ),
    ArgumentSpec(
      name: 'replacement_format',
      kind: ArgumentKind.text,
      required: false,
      describes:
          'a format string for the replacement, where <value> is replaced by the answer value. Defaults to <value>.',
    ),
  ];

  /// The literal text to replace.
  final String placeholder;

  /// The name of the answer whose value is stamped.
  final String valueAnswer;

  /// The tree to restrict to, if any.
  final String? tree;

  /// The format string for the replacement.
  final String? replacementFormat;

  @override
  Future<List<String>> capture(StepContext context) async {
    final String where = tree ?? '.';
    final Command grep = Command('git', <String>['grep', '-l', '-F', placeholder, '--', where]);
    final CommandResult grepResult = await context.shell.run(grep);
    if (!grepResult.ok && grepResult.exitCode != 1) {
      throw CommandFailed(
        argv: grep.argv,
        exitCode: grepResult.exitCode,
        stdout: grepResult.stdout,
        stderr: grepResult.stderr,
      );
    }
    if (grepResult.stdout.trim().isEmpty) {
      return const <String>[];
    }
    return grepResult.stdout.trim().split('\n');
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final String where = tree ?? '.';
    final Command grep = Command('git', <String>['grep', '-l', '-F', placeholder, '--', where]);
    final CommandResult grepResult = await context.shell.run(grep);
    if (!grepResult.ok && grepResult.exitCode != 1) {
      throw CommandFailed(
        argv: grep.argv,
        exitCode: grepResult.exitCode,
        stdout: grepResult.stdout,
        stderr: grepResult.stderr,
      );
    }

    if (grepResult.stdout.trim().isEmpty) {
      return const CheckResult.satisfied('placeholder not found');
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final String rawValue = context.answers.text(valueAnswer);
    final String value = replacementFormat != null
        ? replacementFormat!.replaceAll('<value>', rawValue)
        : rawValue;

    final List<String> files = await capture(context);
    return StepPlan.argv(<String>['sed', '-i', 's/$placeholder/$value/g', ...files]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final String rawValue = context.answers.text(valueAnswer);
    final String value = replacementFormat != null
        ? replacementFormat!.replaceAll('<value>', rawValue)
        : rawValue;

    final List<String> files = await capture(context);
    for (final String file in files) {
      final Command sed = Command('sed', <String>['-i', 's/$placeholder/$value/g', file]);
      final CommandResult result = await context.shell.run(sed);
      if (!result.ok) {
        throw CommandFailed(
          argv: sed.argv,
          exitCode: result.exitCode,
          stdout: result.stdout,
          stderr: result.stderr,
        );
      }
    }
  }

  @override
  Future<void> undo(StepContext context, List<String> captured) async {
    if (captured.isEmpty) return;

    final Command git = Command('git', <String>['checkout', '--', ...captured]);
    final CommandResult result = await context.shell.run(git);
    if (!result.ok) {
      throw CommandFailed(
        argv: git.argv,
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
      );
    }
  }
}
