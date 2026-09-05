// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// A value read off a settings file of the machine instead of copied into an answer.
///
/// The row that reads the file cannot state the wrong value: there is one place it is written, and
/// the row names that place. What is measured here is the other half — that every way the reading
/// can fail is a sentence naming the file and the key, and never an empty value handed on.
void main() {
  const StepName under = StepName('write_cluster_issuer_manifest');
  const String templatePath = 'test/templates/cluster-issuer-manifest.tpl';
  const String manifestPath = '/var/lib/deploy/state/clusterissuer.yaml';
  const String settingsPath = 'clusters/active/<fqdn>.yaml';
  const String settingsHere = 'clusters/active/one.example.org.yaml';

  const String settings =
      'global:\n'
      '  certificates:\n'
      '    acmeServer: https://acme.example.com/directory\n'
      '    email: ops@example.com\n'
      '    empty:\n'
      '    recipients:\n'
      '      - one\n';

  /// The step as a row reading the settings file would build it.
  WriteClusterIssuerManifest reading({
    String acmeKey = 'global.certificates.acmeServer',
    String emailKey = 'global.certificates.email',
    String path = settingsPath,
    String? acmeAnswer,
  }) => WriteClusterIssuerManifest(
    templatePath: templatePath,
    name: 'my-issuer',
    acmeServer: SettingsValue(
      what: 'the certificate authority',
      answer: acmeAnswer,
      key: acmeKey,
      settingsPath: path,
      runAnswer: 'fqdn',
    ),
    ingressClass: 'public',
    path: manifestPath,
    email: const SettingsValue(
      what: 'the mailbox',
      answer: null,
      key: 'global.certificates.email',
      settingsPath: settingsPath,
      runAnswer: 'fqdn',
    ),
  );

  const Arguments answered = Arguments(<String, Object>{'fqdn': 'one.example.org'});

  ClusterMachine machineWith(String? settingsText) {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[templatePath] = File(templatePath).readAsStringSync();
    if (settingsText != null) {
      machine.files.contents[settingsHere] = settingsText;
    }
    return machine;
  }

  test('THE INNOCENT CASE: both values are read off the file, and the slot is filled', () async {
    final ClusterMachine machine = machineWith(settings);
    final StepContext context = machine.contextFor(under, Arguments.none, answered);

    expect(await reading().check(context), isA<Ready>());
    await reading().apply(context);

    final String written = machine.files.contents[manifestPath]!;
    expect(written, contains('server: https://acme.example.com/directory'));
    expect(written, contains('email: ops@example.com'));
  });

  test('a key the file does not carry is refused, and the sentence names both', () async {
    final ClusterMachine machine = machineWith(settings);
    final CheckResult result = await reading(
      acmeKey: 'global.certificates.authority',
    ).check(machine.contextFor(under, Arguments.none, answered));

    expect(result, isA<Blocked>());
    expect(
      (result as Blocked).reason,
      allOf(contains(settingsHere), contains('global.certificates.authority')),
      reason: 'an operator who has to correct a key needs the file and the key in one sentence',
    );
    expect(machine.files.written, isEmpty);
  });

  test('a key holding nothing is refused rather than rendering an empty issuer', () async {
    final ClusterMachine machine = machineWith(settings);
    final CheckResult result = await reading(
      acmeKey: 'global.certificates.empty',
    ).check(machine.contextFor(under, Arguments.none, answered));

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('nothing at all'));
  });

  test('a key holding a list is refused', () async {
    final ClusterMachine machine = machineWith(settings);
    final CheckResult result = await reading(
      acmeKey: 'global.certificates.recipients',
    ).check(machine.contextFor(under, Arguments.none, answered));

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('list or a map'));
  });

  test('a file that is not on the machine is refused, by the filled path', () async {
    final ClusterMachine machine = machineWith(null);
    final CheckResult result = await reading().check(
      machine.contextFor(under, Arguments.none, answered),
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains(settingsHere));
  });

  test('a file that is not YAML is refused', () async {
    final ClusterMachine machine = machineWith('global:\n  certificates:\n   x: "unterminated\n');
    final CheckResult result = await reading().check(
      machine.contextFor(under, Arguments.none, answered),
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('YAML'));
  });

  test('a path whose slot nothing fills is refused rather than read as written', () async {
    final ClusterMachine machine = machineWith(settings);
    final CheckResult result = await reading().check(
      machine.contextFor(under, Arguments.none, Arguments.none),
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('<fqdn>'));
  });

  test('a value named by neither an answer nor a key is refused', () async {
    final ClusterMachine machine = machineWith(settings);
    const WriteClusterIssuerManifest step = WriteClusterIssuerManifest(
      templatePath: templatePath,
      name: 'my-issuer',
      acmeServer: SettingsValue(
        what: 'the certificate authority',
        answer: null,
        key: null,
        settingsPath: null,
        runAnswer: null,
      ),
      ingressClass: 'public',
      path: manifestPath,
      email: SettingsValue(
        what: 'the mailbox',
        answer: null,
        key: 'global.certificates.email',
        settingsPath: settingsPath,
        runAnswer: 'fqdn',
      ),
    );

    final CheckResult result = await step.check(
      machine.contextFor(under, Arguments.none, answered),
    );

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, contains('neither an answer nor a key'));
  });

  test('a key with no settings file beside it is refused', () async {
    final ClusterMachine machine = machineWith(settings);
    final CheckResult result = await reading(
      path: '',
    ).check(machine.contextFor(under, Arguments.none, answered));

    expect(result, isA<Blocked>());
    expect((result as Blocked).reason, isNotEmpty);
  });

  test('a row naming both reads the ANSWER, and says which key it did not read', () async {
    final ClusterMachine machine = machineWith(settings);
    final StepContext context = machine.contextFor(
      under,
      Arguments.none,
      const Arguments(<String, Object>{
        'fqdn': 'one.example.org',
        'authority': 'https://answered.example.com/directory',
      }),
    );

    await reading(acmeAnswer: 'authority').apply(context);

    expect(
      machine.files.contents[manifestPath],
      contains('server: https://answered.example.com/directory'),
      reason: 'what this run was told beats what a file records, as fill_key_value_file decides it',
    );
    expect(
      machine.said.join('\n'),
      allOf(contains('authority'), contains('global.certificates.acmeServer')),
      reason: 'a stale answer beside a live key has to be visible in the record',
    );
  });
}
