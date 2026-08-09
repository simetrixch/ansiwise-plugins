import 'package:ansiwise_api/ansiwise_api.dart';
import 'ensure_tool_prerequisites.dart';

/// Puts the tool that reads structured output on the machine, before anything reads any.
///
/// **It comes first among the tools because things later in the same run use it.** Every reader of a
/// cluster's own answers on this machine is written against it, so a tool phase that installed it
/// last would leave the readers before it with nothing to read with.
///
/// **Its presence is what decides whether to install it, and its version is only reported.** The
/// package manager carries exactly one of these, so no re-run of this step can reach a different
/// version — and failing on the one it carries would make an install that can never end green on a
/// machine whose package manager disagrees with the pin.
final class InstallJq extends ReversibleStep<bool> {
  /// Puts the tool on the machine.
  const InstallJq();

  /// Builds the step from what the program gave it.
  factory InstallJq.fromArguments(Arguments arguments) => const InstallJq();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// What the tool is called, as a command and as a package.
  static const String tool = 'jq';

  @override
  Future<CheckResult> check(StepContext context) async =>
      await EnsureToolPrerequisites.onPath(context, tool)
      ? const CheckResult.satisfied('$tool is on the path')
      : const CheckResult.ready();

  @override
  Future<StepPlan> plan(StepContext context) async => const StepPlan.argv(_argv);

  @override
  Future<void> apply(StepContext context) async {
    // The package manager's answer is not read, for the same reason it is not read when the
    // prerequisites go on: a held lock is not a missing tool. The check that follows asks the
    // machine.
    await context.shell.run(
      const Command.detailed(
        'apt-get',
        arguments: <String>['install', '--yes', tool],
        environment: EnsureToolPrerequisites.quiet,
      ),
    );
  }

  /// Whether the tool is on the path already.
  ///
  /// The undo removes the package, and a machine that carried the tool before this ran would lose
  /// it — the package manager removes what is installed, not what this step installed.
  @override
  Future<bool> capture(StepContext context) => EnsureToolPrerequisites.onPath(context, tool);

  @override
  Future<void> undo(StepContext context, bool captured) async {
    if (captured) {
      return;
    }
    await context.shell.run(
      const Command.detailed(
        'apt-get',
        arguments: <String>['remove', '--yes', tool],
        environment: EnsureToolPrerequisites.quiet,
      ),
    );
  }

  static const List<String> _argv = <String>['apt-get', 'install', '--yes', tool];
}
