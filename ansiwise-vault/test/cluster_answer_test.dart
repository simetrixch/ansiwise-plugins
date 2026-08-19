import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_core/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The SECOND cluster one Vault can serve, and how a row names it.
///
/// **What this axis is for.** The profile can only describe the cluster it stands on, so its
/// `<cluster>` slot always means THIS cluster. A run that builds or removes a SIBLING cluster's
/// surface — its auth mount, its policies, the entries written for it — has to be told which
/// sibling, and `cluster_answer` is the row naming the answer that holds it. The slot is derived
/// from the answer's own name, so the two cannot come apart.
///
/// The tests below are the three directions of it: a row naming the axis gets the sibling's value
/// beside the run answer's in one text, a row naming none fills nothing, and a slot nothing filled
/// is refused with the sibling slot named in the refusal.
void main() {
  const String url = 'https://vault.example.com';
  const String profile =
      'global:\n'
      '  vaultUrl: $url\n'
      '  clusterName: m1\n'
      '  vaultKubernetesAuthPath: kubernetes-m1\n';

  const VaultLayout namingBothAxes = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<stage>.txt',
    runAnswer: 'stage',
    clusterAnswer: 'sibling',
  );

  const VaultLayout namingNone = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault.txt',
  );

  StepContext contextWith(Arguments answers) => StepContext(
    shell: FakeShell(),
    files: FakeFiles(<String, String>{'/srv/checkout/cluster/profile.yaml': profile}),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  test('the sibling value fills its own slot beside the run answer, in one text', () {
    final StepContext context = contextWith(
      const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
    );
    expect(
      namingBothAxes.runAnswerFilled(context, 'secret/data/<stage>/members/<sibling>/keys'),
      'secret/data/dev/members/s1/keys',
    );
    expect(namingBothAxes.runAnswerFilled(context, 'kubernetes-<sibling>'), 'kubernetes-s1');
  });

  test(
    'the profile slots still mean THIS cluster while the sibling slot means the other',
    () async {
      final StepContext context = contextWith(
        const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
      );
      final VaultProfile vault = await vaultProfileFrom(
        context,
        '/srv/checkout',
        layout: namingBothAxes,
      );
      final ArgumentText written = vault.forThisInstallation(
        context,
        '<sibling>-readers over <cluster>\'s store at <stage>',
      );
      expect(written.value, 's1-readers over m1\'s store at dev');
    },
  );

  test(
    'a layout naming no sibling fills nothing, and the refusal names both missing rows',
    () async {
      // The planted defect this guards: a slot silently replaced with an empty string, which reaches
      // Vault as a valid name that grants on the wrong tree.
      final StepContext context = contextWith(
        const Arguments(<String, Object>{'stage': 'dev', 'sibling': 's1'}),
      );
      expect(namingNone.runAnswerFilled(context, 'kubernetes-<sibling>'), 'kubernetes-<sibling>');
      final VaultProfile vault = await vaultProfileFrom(
        context,
        '/srv/checkout',
        layout: namingNone,
      );
      final ArgumentText refused = vault.forThisInstallation(context, 'kubernetes-<sibling>');
      expect(refused.value, isNull);
      expect(refused.refusal, contains('no sibling slot, because the row names no cluster_answer'));
    },
  );

  test(
    'a run not holding the named answer leaves the slot standing, visible in the refusal',
    () async {
      final StepContext context = contextWith(const Arguments(<String, Object>{'stage': 'dev'}));
      final VaultProfile vault = await vaultProfileFrom(
        context,
        '/srv/checkout',
        layout: namingBothAxes,
      );
      final ArgumentText refused = vault.forThisInstallation(context, '<sibling>-readers');
      expect(refused.refusal, contains('<sibling>'));
    },
  );
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
