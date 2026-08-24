import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// Where the profile of ONE installation stands, and why the path is filled rather than taken as
/// written.
///
/// A file an installation declares itself in is named for that installation, so the path a row
/// states carries a slot. Taken literally, the reader looks for a file whose name is the slot —
/// angle brackets and all — and a writer spelling it the same way creates exactly that file. Two
/// sides agreeing on a wrong name is green on both and right on neither, which is how it survives.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://store.m1.example.com';
  const String domain = 'apps1.example.invalid';

  const VaultLayout layout = VaultLayout(
    profile: 'clusters/active/<fqdn>.yaml',
    urlKey: 'global.endpoints.vault.url',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    domainAnswer: 'fqdn',
  );

  StepContext contextOn(FakeFiles files, {Map<String, Object>? answers}) => StepContext(
    shell: FakeShell(),
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: Arguments(answers ?? <String, Object>{'stage': 'dev', 'fqdn': domain}),
    facts: Facts.none,
  );

  const String map =
      'stage: dev\nrole: master\nglobal:\n'
      '  clusterName: m1\n'
      '  vaultKubernetesAuthPath: kubernetes-m1\n'
      '  endpoints:\n    vault:\n      url: $url\n';

  test('the slot is filled from the answer the row names, so one file is read', () async {
    final FakeFiles files = FakeFiles(<String, String>{
      '$repository/clusters/active/$domain.yaml': map,
    });

    final VaultProfile profile = await vaultProfileFrom(
      contextOn(files),
      repository,
      layout: layout,
    );

    expect(profile.refusal, isNull, reason: 'the file the run names is there and was read');
    expect(profile.url, url);
  });

  test('a file at the LITERAL path is not what is read', () async {
    // THE SHAPE THIS CATCHES. A writer that also took the path as written would create exactly this
    // file, and a reader taking it as written would find it — both green, and the installation
    // whose name the slot stands for has no profile at all.
    final FakeFiles files = FakeFiles(<String, String>{
      '$repository/clusters/active/<fqdn>.yaml': map,
    });

    final VaultProfile profile = await vaultProfileFrom(
      contextOn(files),
      repository,
      layout: layout,
    );

    expect(profile.refusal, isNotNull);
    expect(
      profile.refusal,
      contains(domain),
      reason: 'the refusal names the file this run looked for, which is the filled one',
    );
  });

  test('a run holding no such answer leaves the slot visible in the refusal', () async {
    // Left standing rather than replaced by nothing: a path that silently lost its slot reads as a
    // file somebody simply forgot to write.
    final VaultProfile profile = await vaultProfileFrom(
      contextOn(FakeFiles(<String, String>{}), answers: <String, Object>{'stage': 'dev'}),
      repository,
      layout: layout,
    );

    expect(profile.refusal, contains('<fqdn>'));
  });

  test('THE INNOCENT NEIGHBOUR: a path with no slot is unchanged', () async {
    // Without it, a step that mangled every path would satisfy the cases above.
    const VaultLayout fixed = VaultLayout(
      profile: 'installation/profile.yaml',
      urlKey: 'global.endpoints.vault.url',
      nameKey: 'global.clusterName',
      authPathKey: 'global.vaultKubernetesAuthPath',
      credentials: 'secrets/vault-<stage>.txt',
      runAnswer: 'stage',
      domainAnswer: 'fqdn',
    );
    final FakeFiles files = FakeFiles(<String, String>{
      '$repository/installation/profile.yaml': map,
    });

    final VaultProfile profile = await vaultProfileFrom(
      contextOn(files),
      repository,
      layout: fixed,
    );

    expect(profile.refusal, isNull);
    expect(profile.url, url);
  });
}

final class _NothingSaid implements Logger {
  const _NothingSaid();
  @override
  void debug(String message) {}
  @override
  void info(String message) {}
  @override
  void warn(String message) {}
  @override
  void error(String message) {}
}
