import 'package:ansiwise_api/ansiwise_api.dart';

/// Refuses a machine that is not running the operating system release the program pins.
///
/// **The release is a pin like any other version, not a preference.** Everything a program proves
/// is proven on exactly one release: a snap channel that works there can fail on another release at
/// the snap — or worse, silently at the kernel.
///
/// So this refuses rather than warns. A machine on the wrong release can be brought up and will
/// look fine for a while.
final class RequirePinnedUbuntu extends ObservingStep {
  /// Refuses anything that is not [release].
  const RequirePinnedUbuntu(this.release);

  /// Builds the step from what the program gave it.
  factory RequirePinnedUbuntu.fromArguments(Arguments arguments) =>
      RequirePinnedUbuntu(arguments.text('release'));

  /// What this step accepts.
  static const List<ArgumentSpec> arguments = <ArgumentSpec>[
    ArgumentSpec(
      name: 'release',
      kind: ArgumentKind.text,
      describes: 'the operating system release the program pins, as VERSION_ID',
    ),
  ];

  /// The release, as `/etc/os-release` writes it in `VERSION_ID`.
  final String release;

  @override
  Future<CheckResult> check(StepContext context) async {
    if (!await context.files.exists(_osRelease)) {
      return const CheckResult.blocked(
        '/etc/os-release is not there, so this is not a machine this program runs on',
      );
    }

    final Map<String, String> values = _parse(await context.files.read(_osRelease));
    final String? id = values['ID'];
    final String? version = values['VERSION_ID'];

    if (id != 'ubuntu') {
      return CheckResult.blocked(
        'this machine runs ${id ?? 'something /etc/os-release does not name'}, '
        'and the program pins ubuntu $release',
      );
    }
    if (version != release) {
      return CheckResult.blocked(
        'this machine runs ubuntu ${version ?? 'an unnamed release'}, '
        'and the program pins $release',
      );
    }
    return CheckResult.satisfied('ubuntu $release');
  }

  /// Reads the `KEY=value` lines of an os-release file, unquoting the values.
  ///
  /// The format quotes a value only when it needs to, so both `ID=ubuntu` and `ID="ubuntu"` occur
  /// and mean the same thing.
  static Map<String, String> _parse(String content) {
    final Map<String, String> values = <String, String>{};
    for (final String line in content.split('\n')) {
      final int equals = line.indexOf('=');
      if (equals <= 0 || line.startsWith('#')) {
        continue;
      }
      final String key = line.substring(0, equals).trim();
      String value = line.substring(equals + 1).trim();
      if (value.length >= 2 &&
          ((value.startsWith('"') && value.endsWith('"')) ||
              (value.startsWith("'") && value.endsWith("'")))) {
        value = value.substring(1, value.length - 1);
      }
      values[key] = value;
    }
    return values;
  }

  static const String _osRelease = '/etc/os-release';
}
