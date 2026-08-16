import 'package:ansiwise_api/ansiwise_api.dart';

/// Replaces text matching a regular expression in a specific git-tracked file.
///
/// **The file must be named and must exist.** The replacement uses `sed` to update the file in place,
/// and `git checkout` to undo it.
final class ReplaceRegexInTrackedFile extends ReversibleStep<void> {
  /// Replaces occurrences of [pattern] with [replacement] in [path].
  const ReplaceRegexInTrackedFile({
    required this.path,
    required this.pattern,
    required this.replacement,
  });

  /// Builds the step from what the program gave it.
  factory ReplaceRegexInTrackedFile.fromArguments(Arguments arguments) => ReplaceRegexInTrackedFile(
    path: arguments.text('path'),
    pattern: arguments.text('pattern'),
    replacement: arguments.text('replacement'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the path to the file relative to the execution directory',
    ),
    ArgumentSpec(
      name: 'pattern',
      kind: ArgumentKind.text,
      describes: 'the regular expression to match',
    ),
    ArgumentSpec(
      name: 'replacement',
      kind: ArgumentKind.text,
      describes: 'the text to replace the matches with',
    ),
  ];

  /// The path to the file.
  final String path;

  /// The regular expression to match.
  final String pattern;

  /// The replacement text.
  final String replacement;

  @override
  Future<void> capture(StepContext context) async {}

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(path)) {
      return CheckResult.blocked('$path does not exist: the file to modify must exist');
    }

    // Check if there's any match using grep
    final Command grep = Command('grep', <String>['-q', '-E', pattern, path]);

    final CommandResult grepResult = await context.shell.run(grep);
    if (!grepResult.ok && grepResult.exitCode != 1) {
      throw CommandFailed(
        argv: grep.argv,
        exitCode: grepResult.exitCode,
        stdout: grepResult.stdout,
        stderr: grepResult.stderr,
      );
    }

    if (grepResult.exitCode == 1) {
      return const CheckResult.satisfied('pattern not found in file');
    }

    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    return StepPlan.argv(<String>['sed', '-i', '-E', 's/$pattern/$replacement/g', path]);
  }

  @override
  Future<void> apply(StepContext context) async {
    final Command sed = Command('sed', <String>['-i', '-E', 's/$pattern/$replacement/g', path]);
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

  @override
  Future<void> undo(StepContext context, void captured) async {
    final Command git = Command('git', <String>['checkout', '--', path]);
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
