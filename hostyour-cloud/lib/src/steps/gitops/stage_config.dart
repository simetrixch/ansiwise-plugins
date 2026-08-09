/// The one file an installation is switched on and off in, and how a condition reads it.
///
/// Everything on top of a standing cluster can be switched off per stage: a cluster may run without
/// Vault, without an identity provider, without ArgoCD. That decision is not made in a program file,
/// because a program file is the same on every installation; it is made in the stage config of the
/// branch this installation was generated into, which is one of exactly two things an operator fills
/// in by hand.
///
/// **Read here rather than from the environment.** A step or a condition that reaches for an
/// environment variable is invisible to the run's own fingerprint, and two runs differing only in
/// that value would count as the same input. The file is on the machine, it can be opened, and the
/// answer says which file it came from.
library;

import 'package:ansiwise_api/ansiwise_api.dart';

/// Where the branch of this installation is checked out on a machine.
///
/// The same path `deploy-branch` generates the installation into. It is a constant and not an
/// argument because a condition takes none — a condition that needed one would be several
/// conditions, each of which deserves a name a program file can write.
const String branchCheckout = '/srv/hostyour-cloud';

/// Where the stage configs stand inside that checkout.
const String stageConfigDirectory = '$branchCheckout/configs';

/// The prefix of a stage config's file name, before the stage itself.
const String stageConfigPrefix = 'config.';

/// What reading the stage config produced.
final class StageConfig {
  /// Records that [path] was read and holds [values].
  const StageConfig.read({required this.path, required this.values}) : refusal = null;

  /// Records that no stage config could be read, because [refusal].
  const StageConfig.unreadable(this.refusal) : path = null, values = const <String, String>{};

  /// The file the values came from, or null when none was read.
  final String? path;

  /// The `KEY=value` lines of that file.
  final Map<String, String> values;

  /// Why nothing could be read, or null when something was.
  final String? refusal;
}

/// Reads the one stage config of the branch checked out on this machine.
///
/// **One, and it says so when there is not exactly one.** An installation branch is one stage, so
/// the directory carries one config; a checkout that carries none was never generated, and one that
/// carries several is a branch that was never reduced. Both are answers a condition can give, and
/// neither is a guess about which stage was meant.
Future<StageConfig> readStageConfig(PredicateContext context) async {
  if (!await context.files.exists(stageConfigDirectory)) {
    return const StageConfig.unreadable(
      '$stageConfigDirectory is not on this machine, so nothing says what this installation runs',
    );
  }

  final List<String> configs = (await context.files.list(
    stageConfigDirectory,
  )).where((String name) => name.startsWith(stageConfigPrefix)).toList()..sort();

  if (configs.isEmpty) {
    return const StageConfig.unreadable(
      '$stageConfigDirectory holds no $stageConfigPrefix followed by a stage, and that file is what says which '
      'parts of the platform this installation runs',
    );
  }
  if (configs.length > 1) {
    return StageConfig.unreadable(
      '$stageConfigDirectory holds ${configs.join(', ')}, and an installation is one stage — this '
      'branch was never reduced to the one it runs',
    );
  }

  final String path = '$stageConfigDirectory/${configs.first}';
  return StageConfig.read(path: path, values: _assignments(await context.files.read(path)));
}

/// The `KEY=value` lines of a stage config.
///
/// The same shape the seed input is written in, read the same way — into a map, never by running
/// the file.
Map<String, String> _assignments(String content) {
  final Map<String, String> values = <String, String>{};
  for (final String raw in content.split('\n')) {
    final String line = raw.trim().startsWith('export ') ? raw.trim().substring(7) : raw.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    final int equals = line.indexOf('=');
    if (equals <= 0) {
      continue;
    }
    values[line.substring(0, equals).trim()] = _unquoted(line.substring(equals + 1).trim());
  }
  return values;
}

String _unquoted(String value) {
  if (value.length >= 2) {
    final String first = value[0];
    if ((first == '"' || first == "'") && value.endsWith(first)) {
      return value.substring(1, value.length - 1);
    }
  }
  return value;
}
