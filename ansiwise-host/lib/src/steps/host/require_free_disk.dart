import 'package:ansiwise_core/ansiwise_core.dart';

/// Refuses a machine without room for what the installation will put on it.
///
/// The snap, every image the cluster pulls and every volume it creates land here. A machine that
/// runs out halfway through does not fail cleanly: it fails at whichever step happened to be
/// writing, and the operator is left reading that step rather than the disk.
///
/// **The floor is in kibibytes, which is what `df -Pk` writes.** Its blocks are 1024 bytes, so the
/// argument, the comparison and both messages are all in that one unit and nothing here converts.
/// A step that converted would have to name the unit it converted TO, and a name that disagrees
/// with the arithmetic is what a person reads when they choose the floor.
final class RequireFreeDisk extends ObservingStep {
  /// Refuses [path] when it has less than [freeKibibytes] free.
  const RequireFreeDisk({required this.path, required this.freeKibibytes});

  /// Builds the step from what the program gave it.
  factory RequireFreeDisk.fromArguments(Arguments arguments) => RequireFreeDisk(
    path: arguments.text('path'),
    freeKibibytes: arguments.integer('free_kibibytes'),
  );

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
      name: 'free_kibibytes',
      kind: ArgumentKind.integer,
      band: IntegerBand.between(
        least: 65536,
        most: 1099511627776,
        because:
            '64 MiB is less than any installation needs free, so a smaller floor is a unit mistake, and 1 PiB is above the largest file system one stands on',
      ),
      describes: 'the least free space the installation needs there, as df -Pk reports it in KiB',
    ),
  ];

  /// The directory whose file system is measured.
  final String path;

  /// The least free space it needs, in kibibytes.
  final int freeKibibytes;

  @override
  Future<CheckResult> check(StepContext context) async {
    // POSIX output and 1024-byte blocks, so the columns are the same everywhere and the number needs
    // no unit parsing. Without -P a long device name wraps onto its own line and the columns move.
    final CommandResult measured = await context.shell.run(
      Command.observing('df', arguments: <String>['-Pk', path]),
    );
    if (!measured.ok) {
      return CheckResult.blocked('df could not measure $path: ${measured.stderr.trim()}');
    }

    final int? available = _availableKibibytes(measured.stdout);
    if (available == null) {
      return CheckResult.blocked('df answered something $path cannot be read out of');
    }

    if (available < freeKibibytes) {
      return CheckResult.blocked(
        '$path has $available KiB free and the installation needs $freeKibibytes KiB',
      );
    }
    return CheckResult.satisfied('$available KiB free on $path');
  }

  /// The fourth column of the second line: available blocks, which `-k` makes 1024 bytes each.
  static int? _availableKibibytes(String output) {
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
