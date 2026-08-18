import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a machine without room for what the installation will put on it.
///
/// The snap, every image the cluster pulls and every volume it creates land here. A machine that
/// runs out halfway through does not fail cleanly: it fails at whichever step happened to be
/// writing, and the operator is left reading that step rather than the disk.
final class RequireFreeDisk extends ObservingStep {
  /// Refuses [path] when it has less than [gigabytes] free.
  const RequireFreeDisk({required this.path, required this.gigabytes});

  /// Builds the step from what the program gave it.
  factory RequireFreeDisk.fromArguments(Arguments arguments) =>
      RequireFreeDisk(path: arguments.text('path'), gigabytes: arguments.integer('gigabytes'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'path',
      kind: ArgumentKind.text,
      describes: 'the directory whose file system is measured',
      defaultValue: '/',
    ),
    // No default: the floor is the product's sizing, so the program row states it.
    ArgumentSpec(
      name: 'gigabytes',
      kind: ArgumentKind.integer,
      describes: 'the least free space the installation needs there',
    ),
  ];

  /// The directory whose file system is measured.
  final String path;

  /// The least free space it needs, in gigabytes.
  final int gigabytes;

  @override
  Future<CheckResult> check(StepContext context) async {
    // POSIX output and kilobyte blocks, so the columns are the same everywhere and the number needs
    // no unit parsing. Without -P a long device name wraps onto its own line and the columns move.
    final CommandResult measured = await context.shell.run(
      Command.observing('df', arguments: <String>['-Pk', path]),
    );
    if (!measured.ok) {
      return CheckResult.blocked('df could not measure $path: ${measured.stderr.trim()}');
    }

    final int? availableKilobytes = _availableKilobytes(measured.stdout);
    if (availableKilobytes == null) {
      return CheckResult.blocked('df answered something $path cannot be read out of');
    }

    final int availableGigabytes = availableKilobytes ~/ (1000 * 1000);
    if (availableGigabytes < gigabytes) {
      return CheckResult.blocked(
        '$path has $availableGigabytes GB free and the installation needs $gigabytes GB',
      );
    }
    return CheckResult.satisfied('$availableGigabytes GB free on $path');
  }

  /// The fourth column of the second line: available blocks.
  static int? _availableKilobytes(String output) {
    final List<String> lines = output
        .split('\n')
        .where((String line) => line.trim().isNotEmpty)
        .toList();
    if (lines.length < 2) {
      return null;
    }
    final List<String> columns = lines[1].split(RegExp(r'\s+'));
    if (columns.length < 4) {
      return null;
    }
    return int.tryParse(columns[3]);
  }
}
