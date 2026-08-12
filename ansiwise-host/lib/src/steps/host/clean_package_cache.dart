import 'package:ansiwise_api/ansiwise_api.dart';

/// Removes the package archives apt downloaded to install with.
///
/// They are of no use once the packages are installed, and on a machine sized for a cluster the
/// space matters more than the saved download would.
///
/// The postcondition is that the archive directory holds no `.deb`, which is read from the
/// directory rather than from what the command returned.
final class CleanPackageCache extends IrreversibleStep {
  /// Empties the archive directory.
  const CleanPackageCache();

  /// Builds the step from what the program gave it.
  factory CleanPackageCache.fromArguments(Arguments arguments) => const CleanPackageCache();

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[];

  /// Where apt keeps what it downloaded.
  static const String archives = '/var/cache/apt/archives';

  @override
  String get irreversibleReason =>
      'the archives are deleted, and nothing recorded which of them were there to fetch again';

  @override
  Future<CheckResult> check(StepContext context) async {
    final int count = await _archiveCount(context);
    if (count == 0) {
      return const CheckResult.satisfied('the package archive is empty');
    }
    return const CheckResult.ready();
  }

  @override
  Future<StepPlan> plan(StepContext context) async {
    final int count = await _archiveCount(context);
    context.log.info(
      count == 1
          ? '1 downloaded archive would be deleted'
          : '$count downloaded archives would be deleted',
    );
    return const StepPlan.argv(<String>['apt-get', 'clean']);
  }

  @override
  Future<void> apply(StepContext context) async {
    final CommandResult cleaned = await context.shell.run(
      const Command.detailed('apt-get', arguments: <String>['clean'], elevated: true),
    );
    if (!cleaned.ok) {
      throw CommandFailed(
        argv: const <String>['apt-get', 'clean'],
        exitCode: cleaned.exitCode,
        stdout: '',
        stderr: cleaned.stderr,
      );
    }
  }

  Future<int> _archiveCount(StepContext context) async {
    if (!await context.files.exists(archives)) {
      return 0;
    }
    final List<String> entries = await context.files.list(archives);
    return entries.where((String name) => name.endsWith('.deb')).length;
  }
}
