import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:test/test.dart';

/// The one axis a product may run the same Vault layout along more than once, and the demotion of
/// its name out of this package.
///
/// **What this used to be.** Every registry entry declared the answer `stage`, every path and every
/// policy rule was filled from a slot spelled `<stage>`, and the policy step read that answer
/// unconditionally. Vault has no such thing: a product with three environments wants one tree per
/// environment, one with three regions wants one per region, and one with neither wants a single
/// tree — so a vendor whose product has no stage could not use the package at all, because the
/// resolver refuses a program that does not declare an answer a step says it reads.
///
/// **What it is now.** The row names the answer under `run_answer`, and the slot is derived from
/// that name so the two cannot come apart. Leaving it off is a first-class case and not a mistake.
///
/// The tests below are the two directions of that: a product WITH such an axis gets its value in
/// every path and rule, and a product WITHOUT one is not refused for lacking a name this package
/// used to insist on.
void main() {
  const String repository = '/srv/checkout';
  const String url = 'https://vault.example.com';
  const String profile =
      'global:\n'
      '  vaultUrl: $url\n'
      '  clusterName: m1\n'
      '  vaultKubernetesAuthPath: kubernetes-m1\n';

  const VaultLayout namingAnAxis = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault-<region>.txt',
    runAnswer: 'region',
  );

  const VaultLayout namingNone = VaultLayout(
    profile: 'cluster/profile.yaml',
    urlKey: 'global.vaultUrl',
    nameKey: 'global.clusterName',
    authPathKey: 'global.vaultKubernetesAuthPath',
    credentials: 'secrets/vault.txt',
  );

  StepContext contextWith(Arguments answers, {FakeFiles? files}) => StepContext(
    shell: FakeShell(),
    files: files ?? FakeFiles(<String, String>{}),
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _NothingSaid(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: answers,
    facts: Facts.none,
  );

  group('the name of the axis is the program row', () {
    test('the slot is derived from the answer, so the two cannot come apart', () {
      expect(namingAnAxis.runSlot, '<region>');
      expect(namingNone.runSlot, isNull);
    });

    test('the value fills the slot wherever it stands, under whatever name the row chose', () {
      // "region" and not "stage": the word is the product's, and nothing in this package holds one.
      final StepContext context = contextWith(
        const Arguments(<String, Object>{'region': 'eu-west'}),
      );
      expect(
        namingAnAxis.runAnswerFilled(context, 'secret/data/<region>/app/*'),
        'secret/data/eu-west/app/*',
      );
      expect(
        vaultCredentialsPath(context, repository, layout: namingAnAxis),
        '$repository/secrets/vault-eu-west.txt',
      );
    });

    test('a layout naming no axis fills nothing at all', () {
      final StepContext context = contextWith(const Arguments(<String, Object>{'stage': 'dev'}));
      expect(
        namingNone.runAnswerFilled(context, 'secret/data/<stage>/app/*'),
        'secret/data/<stage>/app/*',
      );
      expect(
        vaultCredentialsPath(context, repository, layout: namingNone),
        '$repository/secrets/vault.txt',
      );
    });
  });

  group('a product with no such axis', () {
    test('is refused by nothing this package declares', () {
      // The refusal that used to make the package unusable: the resolver holds a program to every
      // answer a registry entry says its step reads, so one name here made that name mandatory for
      // every vendor. There is none now.
      final Set<String> read = <String>{
        for (final RegisteredStep entry in vaultRegistry.steps.values) ...entry.answers,
      };
      expect(
        read,
        isEmpty,
        reason:
            'an answer named in a registry entry is an answer every program running that step has '
            'to declare, whatever the product is about',
      );
    });

    test('states nothing for the axis, and the declaration lets it', () {
      // Read off every step rather than off one, because the family declares the layout ONCE and a
      // step that stopped spreading that list would take the name back into its own hands.
      for (final RegisteredStep entry in vaultRegistry.steps.values) {
        final Iterable<ArgumentSpec> found = entry.arguments.where(
          (ArgumentSpec spec) => spec.name == 'run_answer',
        );
        expect(found, hasLength(1), reason: '${entry.name} declares no run_answer');
        expect(found.first.required, isFalse, reason: 'a product with no such axis names none');
        expect(
          found.first.hasDefault,
          isFalse,
          reason: 'a default here would be one product\'s axis, named for every vendor again',
        );
      }
    });
  });

  group('a slot nothing filled', () {
    test('is refused with the slot still in it, rather than looked for on disk', () async {
      // A path called `vault-<region>.txt` is not on the machine either way. The refusal that said
      // only "not on this host" would send an operator looking for a file nobody meant to write.
      final RootToken token = await rootTokenFrom(
        contextWith(const Arguments(<String, Object>{})),
        '$repository/secrets/vault-<region>.txt',
      );
      expect(token.value, isNull);
      expect(token.refusal, contains('<region>'));
      expect(token.refusal, contains('nothing in this run holds that name'));
    });

    test('a path with every slot filled is read rather than refused', () async {
      // The other half: without it, a refusal fired at every path would pass the test above while
      // saying nothing about an unfilled slot in particular.
      const String path = '$repository/secrets/vault-eu-west.txt';
      final RootToken token = await rootTokenFrom(
        contextWith(
          const Arguments(<String, Object>{}),
          files: FakeFiles(<String, String>{path: 'Root Token: hvs.NotARealToken\n'}),
        ),
        path,
      );
      expect(token.refusal, isNull);
      expect(token.value, 'hvs.NotARealToken');
    });

    test('a rule carrying a slot the row never named is refused before it reaches Vault', () async {
      final StepContext context = contextWith(
        const Arguments(<String, Object>{'stage': 'dev'}),
        files: FakeFiles(<String, String>{'$repository/cluster/profile.yaml': profile}),
      );
      final VaultProfile read = await vaultProfileFrom(context, repository, layout: namingNone);
      final ArgumentText written = read.forThisInstallation(
        context,
        'path "secret/data/<stage>/app/*" { capabilities = ["read"] }',
      );
      expect(written.value, isNull);
      expect(written.refusal, contains('<stage>'));
    });
  });
}

/// A logger for a test that measures values rather than what a step said.
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
