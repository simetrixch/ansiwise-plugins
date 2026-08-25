import 'package:ansiwise_core/ansiwise_core.dart';

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
    this.elevated = false,
  });

  /// Builds the step from what the program gave it.
  factory ReplaceRegexInTrackedFile.fromArguments(Arguments arguments) => ReplaceRegexInTrackedFile(
    path: arguments.text('path'),
    pattern: arguments.text('pattern'),
    replacement: arguments.text('replacement'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
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
    elevationArgument,
  ];

  /// The path to the file.
  final String path;

  /// The regular expression to match.
  final String pattern;

  /// The replacement text.
  final String replacement;

  /// Whether the file this row points at belongs to root, so every read and write of it is
  /// elevated.
  final bool elevated;
  @override
  Future<void> capture(StepContext context) async {}

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(path, elevated: elevated)) {
      return CheckResult.blocked('$path does not exist: the file to modify must exist');
    }

    // OBSERVING, because searching a file for a pattern changes nothing — and undeclared, the
    // planning ports refuse it, which makes the whole step unmeasurable in the two modes whose
    // purpose is measuring rather than reporting that the pattern is absent.
    final Command grep = Command.observing(
      'grep',
      arguments: <String>['-q', '-E', pattern, path],
      elevated: elevated,
    );

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
    // ELEVATED WITH THE READS ABOVE. `sed -i` writes a new file beside the old one and renames it
    // over it, so it needs the same reach into the directory that the check's read of this path
    // needed. Unelevated against a path root owns it fails after the check said ready, which is the
    // one shape a row's answer exists to prevent. The plain constructor cannot carry the answer at
    // all, so the composition says how it runs.
    final Command sed = Command.detailed(
      'sed',
      arguments: <String>['-i', '-E', 's/$pattern/$replacement/g', path],
      elevated: elevated,
    );
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
    // The take-back writes the same file the apply wrote, so it reaches for it the same way. An undo
    // that cannot write what its step wrote leaves the record saying the change was taken back while
    // the file still carries it.
    final Command git = Command.detailed(
      'git',
      arguments: <String>['checkout', '--', path],
      elevated: elevated,
    );
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
