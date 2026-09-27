import 'package:ansiwise_core/ansiwise_core.dart';

/// Removes a directory and everything in it, where a machine still carries one the platform no
/// longer uses — a checkout that moved to another path, say.
///
/// **Absent is done.** A machine that never carried the directory, or one an earlier run already
/// took it from, has nothing to do, so the row can stand in a program every machine runs.
///
/// **Only a path deep enough to be the platform's own.** The path is absolute, carries no `.` or
/// `..` segment, and stands at least two levels deep (`/srv/<name>`). A row naming `/`, `/srv` or
/// `/home` would take the machine's own tree with it, so such a row is refused before anything is
/// asked of the machine.
final class RemoveDirectory extends IrreversibleStep {
  /// Removes [path] and everything under it.
  const RemoveDirectory({required this.path, this.elevated = false});

  /// Builds the step from what the program gave it.
  factory RemoveDirectory.fromArguments(Arguments arguments) => RemoveDirectory(
    path: arguments.text('path'),
    elevated: arguments.has('elevated') && arguments.flag('elevated'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes:
          'the absolute path of the directory to remove, at least two levels deep, such as /srv/<name>',
    ),
    elevationArgument,
  ];

  /// The directory to remove.
  final String path;

  /// Whether the directory belongs to root, so the check and the removal are elevated.
  final bool elevated;

  @override
  String get irreversibleReason =>
      'what the directory held is gone from the machine, and nothing on it keeps a copy';

  /// Why [path] is not one this step may remove, or null where it may.
  String? get _refusal {
    if (!path.startsWith('/')) return '$path is not an absolute path';
    final List<String> segments = path.split('/').where((String s) => s.isNotEmpty).toList();
    if (segments.any((String s) => s == '.' || s == '..')) {
      return '$path carries a "." or ".." segment, so where it leads is not what it reads';
    }
    if (segments.length < 2) {
      return '$path is fewer than two levels deep, and removing it would take the machine\'s own tree with it';
    }
    return null;
  }

  @override
  Future<CheckResult> check(StepContext context) async {
    final String? refusal = _refusal;
    if (refusal != null) return CheckResult.blocked(refusal);
    if (!await context.files.exists(path, elevated: elevated)) {
      return CheckResult.satisfied('$path is not on this machine, so there is nothing to remove');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async =>
      StepPlan.argv(<String>['rm', '-rf', '--', path]);

  @override
  Future<void> apply(StepContext context) => context.files.delete(path, elevated: elevated);
}
