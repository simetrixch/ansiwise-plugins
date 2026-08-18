// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
// The template is read off the disk rather than pasted in, because a copy could name a slot the
// step does not fill or lose one it does, and every assertion here would go on passing while the
// file a caller ships is broken.
import 'dart:io';

import 'package:ansiwise_core/ansiwise_core.dart';
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:test/test.dart';

import 'support/machine.dart';

/// The certificate issuer as it is rendered, before anything applies it.
void main() {
  const StepName under = StepName('write_cluster_issuer_manifest');

  // Where a program row would name the template, and where it says the rendered file goes. Both are
  // this caller's arrangement: cert-manager mandates neither, so this package carries neither.
  const String templatePath = 'test/templates/cluster-issuer-manifest.tpl';
  const String manifestPath = '/var/lib/deploy/state/clusterissuer.yaml';
  const String mailboxAnswer = 'certificate_mailbox';
  const String authorityAnswer = 'certificate_authority';

  const WriteClusterIssuerManifest step = WriteClusterIssuerManifest(
    templatePath: templatePath,
    name: 'my-issuer',
    acmeServerAnswer: authorityAnswer,
    ingressClass: 'public',
    path: manifestPath,
    emailAnswer: mailboxAnswer,
  );

  /// The name the ROW gives the answer holding the mailbox.
  ///
  /// Deliberately not the word one certificate authority uses. The step is told which answer to read
  /// by its row, so a test naming that authority's own word would pass even if the step ignored the
  /// row and reached for it directly.

  /// A machine carrying the template a program row names, the way a real one carries it.
  ClusterMachine withTemplate() {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[templatePath] = File(templatePath).readAsStringSync();
    return machine;
  }

  /// What an operator answered about this installation.
  const Arguments answered = Arguments(<String, Object>{
    mailboxAnswer: 'ops@example.com',
    authorityAnswer: 'https://acme.example.com/directory',
  });

  test('the four values the row and the run hold reach the file', () async {
    final ClusterMachine machine = withTemplate();
    final StepContext context = machine.contextFor(under, Arguments.none, answered);

    expect(await step.check(context), isA<Ready>());
    await step.apply(context);

    final String written = machine.files.contents[manifestPath]!;
    expect(written, contains('kind: ClusterIssuer'));
    expect(written, contains('name: my-issuer'));
    expect(written, contains('server: https://acme.example.com/directory'));
    expect(written, contains('email: ops@example.com'));
    expect(written, contains('ingressClassName: public'));
    expect(await step.check(context), isA<Satisfied>());
  });

  test('the mailbox is the one this run answered, whatever it reads like', () async {
    // Nothing here recognises an illustration. It is the operator's own address, and a rule of that
    // kind would refuse whoever's mailbox happens to read like an example.
    final ClusterMachine machine = withTemplate();
    await step.apply(
      machine.contextFor(
        under,
        Arguments.none,
        const Arguments(<String, Object>{
          mailboxAnswer: 'certificates@example.org',
          authorityAnswer: 'https://acme.example.com/directory',
        }),
      ),
    );
    expect(machine.files.contents[manifestPath], contains('email: certificates@example.org'));
  });

  test('the directory the row named is created before the file is written', () async {
    final ClusterMachine machine = withTemplate();
    await step.apply(machine.contextFor(under, Arguments.none, answered));
    expect(machine.files.directories, contains('/var/lib/deploy/state'));
  });

  test('a machine carrying no template is refused rather than writing an empty file', () async {
    // The template travels with the programs of an installation. A machine that has none cannot be
    // told what its file should hold, and guessing would put a manifest on the cluster that names
    // nothing this run decided.
    final ClusterMachine machine = ClusterMachine();
    expect(await step.check(machine.contextFor(under, Arguments.none, answered)), isA<Blocked>());
    expect(machine.files.written, isEmpty);
  });

  test('a second run writes nothing at all', () async {
    final ClusterMachine machine = withTemplate();
    final StepContext context = machine.contextFor(under, Arguments.none, answered);
    await step.apply(context);
    machine.files.written.clear();

    expect(await step.check(context), isA<Satisfied>());
    expect(machine.files.written, isEmpty);
  });

  test('the rendered file that stood before is what an undo puts back', () async {
    final ClusterMachine machine = withTemplate();
    final StepContext context = machine.contextFor(under, Arguments.none, answered);
    machine.files.contents[manifestPath] = 'kind: ClusterIssuer\nmetadata:\n  name: an-older-one\n';

    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);
    expect(machine.files.contents[manifestPath], contains('name: an-older-one'));
  });

  test('a machine that had none is left with none', () async {
    final ClusterMachine machine = withTemplate();
    final StepContext context = machine.contextFor(under, Arguments.none, answered);

    final String? captured = await step.capture(context);
    await step.apply(context);
    await step.undo(context, captured);
    expect(machine.files.contents.containsKey(manifestPath), isFalse);
  });

  // THE REASON THE AUTHORITY IS AN ANSWER AT ALL. A machine that exists to prove a run registers
  // with the staging service, whose issuing is not rationed; a machine that serves registers with
  // the production one, which counts every repeated proof against a weekly allowance. Both read the
  // same program row, so a step reaching for one of them itself would spend the other's budget.
  test('another installation answers another authority, and the file follows it', () async {
    final ClusterMachine machine = withTemplate();
    await step.apply(
      machine.contextFor(
        under,
        Arguments.none,
        const Arguments(<String, Object>{
          mailboxAnswer: 'ops@example.com',
          authorityAnswer: 'https://acme-staging-v02.api.letsencrypt.org/directory',
        }),
      ),
    );
    expect(
      machine.files.contents[manifestPath],
      contains('server: https://acme-staging-v02.api.letsencrypt.org/directory'),
    );
  });
}
