import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The address a row of another package is pointed at, published out of the profile and never built
/// out of anything else.
///
/// **What the three cases are for.** The first is the whole point of the step: a later row asks the
/// same Vault the rows around it ask, so the value it takes has to be the value those rows use — the
/// text the profile carries, read rather than composed. The second is the refusal, and its second
/// assertion is the load-bearing one: an empty publication is a value the row after it cannot tell
/// from a real address. The third is the innocent case that keeps that refusal from spreading to the
/// two profile keys this step never reads.
void main() {
  const String repository = '/srv/checkout';
  const String profilePath = '$repository/installation/profile.yaml';

  const MeasureVaultUrl step = MeasureVaultUrl(
    repository: repository,
    layout: VaultLayout(
      profile: 'installation/profile.yaml',
      urlKey: 'global.vaultUrl',
      nameKey: 'global.clusterName',
      authPathKey: 'global.vaultKubernetesAuthPath',
      credentials: 'secrets/vault-<stage>.txt',
    ),
  );

  ({StepContext context, Map<MeasurementName, String> published}) runOver(String profile) {
    final Map<MeasurementName, String> published = <MeasurementName, String>{};
    return (
      context: StepContext(
        shell: FakeShell(),
        files: FakeFiles(<String, String>{profilePath: profile}),
        http: FakeHttp(),
        clock: FakeClock(),
        entropy: FakeEntropy(),
        log: const _SilentLog(),
        step: const StepName('measure_vault_url'),
        arguments: Arguments.none,
        answers: Arguments.none,
        facts: Facts.none,
        measurements: _Sink(published),
      ),
      published: published,
    );
  }

  test('it publishes the address the profile records, and never one it composed', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOver(
      'global:\n  vaultUrl: https://one.example\n  clusterName: m1\n',
    );

    expect(await step.check(it.context), isA<Satisfied>());
    expect(it.published[const MeasurementName('vault_url')], 'https://one.example');
  });

  test('a profile with no address refuses and publishes nothing', () async {
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOver(
      'global:\n  clusterName: m1\n',
    );

    final CheckResult answer = await step.check(it.context);
    expect(answer, isA<Blocked>());
    expect((answer as Blocked).reason, contains('global.vaultUrl'));
    expect(it.published, isEmpty);
  });

  test('THE INNOCENT NEIGHBOUR: the two keys this step never reads are not demanded', () async {
    // This step reads one key. Refusing on the other two would make every row that wants the
    // address demand keys nothing here looks at, on a profile that is perfectly good for it.
    final ({StepContext context, Map<MeasurementName, String> published}) it = runOver(
      'global:\n  vaultUrl: https://one.example\n',
    );

    expect(await step.check(it.context), isA<Satisfied>());
    expect(it.published[const MeasurementName('vault_url')], 'https://one.example');
  });
}

/// A log nothing reads, so a probe measures what a step DID and not what it said about it.
final class _SilentLog implements Logger {
  const _SilentLog();

  @override
  void debug(String message) {}

  @override
  void info(String message) {}

  @override
  void warn(String message) {}

  @override
  void error(String message) {}
}

/// Collects what a step publishes, so a probe can read it.
final class _Sink implements MeasurementSink {
  const _Sink(this._into);

  final Map<MeasurementName, String> _into;

  @override
  void publish(MeasurementName name, String value) => _into[name] = value;
}
