import 'package:ansiwise_api/ansiwise_api.dart';

/// Refuses a machine that is too small for what the platform asks of it.
///
/// The floors are not a guess. They are what the platform's own resource requests add up to, and
/// they are measured with `nproc` and `/proc/meminfo`.
///
/// **Memory is measured in kilobytes against 15,000,000 and not against 16 GiB.** `MemTotal` reports
/// what is left after the kernel's own reservations — about 15.3 to 16.3 GiB on a real 16 GB
/// machine — so a floor written as exactly 16 GiB refuses the very machines the minimum names. That
/// was found on a real machine, and writing the round number back is how it comes back.
final class RequireMachineSize extends ObservingStep {
  /// Refuses anything below [vcpu] processors or [memoryKilobytes] of memory.
  const RequireMachineSize({required this.vcpu, required this.memoryKilobytes});

  /// Builds the step from what the program gave it.
  factory RequireMachineSize.fromArguments(Arguments arguments) => RequireMachineSize(
    vcpu: arguments.integer('vcpu'),
    memoryKilobytes: arguments.integer('memory_kilobytes'),
  );

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'vcpu',
      kind: ArgumentKind.integer,
      describes: 'the fewest processors the platform fits on',
      defaultValue: 8,
    ),
    ArgumentSpec(
      name: 'memory_kilobytes',
      kind: ArgumentKind.integer,
      describes: 'the least memory, as /proc/meminfo reports it after kernel reservations',
      defaultValue: 15000000,
    ),
  ];

  /// The fewest processors the platform fits on.
  final int vcpu;

  /// The least memory, in kilobytes as `MemTotal` reports it.
  final int memoryKilobytes;

  @override
  Future<CheckResult> check(StepContext context) async {
    final CommandResult processors = await context.shell.run(const Command.observing('nproc'));
    if (!processors.ok) {
      return const CheckResult.blocked('nproc did not answer, so the machine cannot be measured');
    }
    final int? found = int.tryParse(processors.trimmed);
    if (found == null) {
      return CheckResult.blocked('nproc answered "${processors.trimmed}", which is not a number');
    }
    if (found < vcpu) {
      return CheckResult.blocked('this machine has $found processors and the platform needs $vcpu');
    }

    final int? memory = await _memoryKilobytes(context);
    if (memory == null) {
      return const CheckResult.blocked('/proc/meminfo carries no MemTotal line to measure');
    }
    if (memory < memoryKilobytes) {
      return CheckResult.blocked(
        'this machine reports $memory kB of memory and the platform needs $memoryKilobytes kB',
      );
    }

    return CheckResult.satisfied('$found processors and $memory kB of memory');
  }

  Future<int?> _memoryKilobytes(StepContext context) async {
    if (!await context.files.exists(_memInfo)) {
      return null;
    }
    for (final String line in (await context.files.read(_memInfo)).split('\n')) {
      if (!line.startsWith('MemTotal:')) {
        continue;
      }
      // `MemTotal:       16087564 kB` — the number is the only digits on the line.
      final RegExp digits = RegExp(r'(\d+)');
      final RegExpMatch? match = digits.firstMatch(line);
      if (match == null) {
        return null;
      }
      return int.tryParse(match.group(1) ?? '');
    }
    return null;
  }

  static const String _memInfo = '/proc/meminfo';
}
