import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

/// The two files an operator's answers become, and the three rules that decide what goes into them.
///
/// Every case here is an incident the shell implementation paid for. A file was rewritten from the
/// template on a re-run and the root token of a running Vault went with it. A value copied straight
/// out of the template was taken for an answer, and certificate mail went to a mailbox nobody reads.
/// An in-place rewrite reported success for a key the template does not declare, and the file kept
/// nothing at all — which surfaced much later, as the Vault seed refusing an empty row.
void main() {
  const String repository = '/srv/hostyour-cloud';
  const String fqdn = 'm1.example.com';
  const String configTemplate = '$repository/configs/config.example';
  const String configPath = '$repository/configs/config.dev';
  const String secretsTemplate = '$repository/secrets/secrets.example';
  const String secretsPath = '$repository/secrets/secrets.dev';

  const WriteStageConfig writeConfig = WriteStageConfig(repository: repository);
  const WriteStageSecrets writeSecrets = WriteStageSecrets(repository: repository);

  /// The template as the trunk ships it: every value at a placeholder, every key explained.
  const String configExample =
      '# The mailbox certificate notices go to.\n'
      'LETSENCRYPT_EMAIL="user@example.com"\n'
      '# The first administrator of the identity provider.\n'
      'IDP_BOOTSTRAP_EMAIL="user@example.com"\n'
      'ALERT_RECIPIENTS=""\n'
      'UNIT_APEX=""\n'
      'PLATFORM_DOMAIN=""\n'
      'BUILD_PLANE=""\n'
      'CATALOG_REPO=""\n'
      'CLUSTER_NAME="my-cluster"\n'
      'DOMAIN_SUFFIX="example.com"\n'
      'DEPLOY_ENV="prod"\n'
      '# A platform default nobody is asked for.\n'
      'POD_CIDR="10.244.0.0/16"\n';

  const String secretsExample =
      '# The credentials a third party issues.\n'
      'GITOPS_REPO_PAT=""\n'
      'GITOPS_REPO_READ_PAT=""\n'
      'CLOUDFLARE_API_TOKEN=""\n'
      'STORAGE_BOX_HOST=""\n'
      'STORAGE_BOX_USER=""\n'
      'STORAGE_BOX_PASSWORD=""\n'
      'REGISTRY_DOCKERHUB_USER=""\n'
      'REGISTRY_DOCKERHUB_TOKEN=""\n'
      'BUILD_HOSTYOUR_CLOUD_REPO_PAT=""\n'
      'BUILD_CATALOG_REPO_PAT=""\n'
      '# Written back once this installation is running.\n'
      'VAULT_ROOT_TOKEN=""\n';

  Arguments answering({
    String stage = 'dev',
    String buildPlane = fqdn,
    String letsencryptEmail = 'certs@example.com',
    String alertRecipient = 'alerts@example.com',
    Map<String, Object> without = const <String, Object>{},
  }) {
    final Map<String, Object> given = <String, Object>{
      'fqdn': fqdn,
      'stage': stage,
      'build_plane': buildPlane,
      'unit_apex': 'example.com',
      'platform_domain': 'example.com',
      'alert_recipients': <String>[alertRecipient],
      'catalog_repo': 'example-org/tenant-catalog',
      'letsencrypt_email': letsencryptEmail,
      'idp_bootstrap_email': 'admin@example.com',
      'gitops_repo_pat': 'writer-credential-0001',
      'gitops_repo_read_pat': 'reader-credential-0001',
      'cloudflare_api_token': 'cloudflare-credential-0001',
      'storage_box_host': 'u000000.your-storagebox.de',
      'storage_box_user': 'u000000-sub1',
      'storage_box_password': 'storage-credential-0001',
      'registry_dockerhub_user': 'example-hub-user',
      'registry_dockerhub_token': 'dockerhub-credential-0001',
      'build_hostyour_cloud_repo_pat': 'build-credential-0001',
      'build_catalog_repo_pat': 'catalog-credential-0001',
      ...without,
    };
    for (final String name in without.keys) {
      if (without[name] == '') {
        given.remove(name);
      }
    }
    return Arguments(given);
  }

  StepContext contextOn(FakeFiles files, {Arguments? answers}) => StepContext(
    shell: FakeShell(),
    files: files,
    http: FakeHttp(),
    clock: FakeClock(),
    entropy: FakeEntropy(),
    log: const _SilentLog(),
    step: const StepName('under_test'),
    arguments: Arguments.none,
    answers: answers ?? answering(),
    facts: Facts.none,
  );

  FakeFiles tree({String? config, String? secrets}) => FakeFiles(<String, String>{
    configTemplate: configExample,
    secretsTemplate: secretsExample,
    configPath: ?config,
    secretsPath: ?secrets,
  });

  group('the config file the rest of the installation reads', () {
    test('a branch with no config gets one, filled from the answers', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      await writeConfig.apply(context);

      expect(files.contents[configPath], contains('LETSENCRYPT_EMAIL="certs@example.com"'));
      expect(files.contents[configPath], contains('DEPLOY_ENV="dev"'));
      expect(await writeConfig.check(context), isA<Satisfied>());
    });

    test('a value still equal to the template is not an answer, and is filled', () async {
      // The mailbox the template carries is one nobody reads. Taking it for an answer put
      // certificate mail and the identity provider's first account on user@example.com.
      final FakeFiles files = tree(config: configExample);

      expect(await writeConfig.check(contextOn(files)), isA<Ready>());
      await writeConfig.apply(contextOn(files));
      expect(files.contents[configPath], isNot(contains('user@example.com')));
      expect(files.contents[configPath], contains('IDP_BOOTSTRAP_EMAIL="admin@example.com"'));
    });

    test('a value an operator set by hand is never reset by a later run', () async {
      final FakeFiles files = tree(
        config: configExample.replaceAll(
          'ALERT_RECIPIENTS=""',
          'ALERT_RECIPIENTS="oncall@example.com"',
        ),
      );

      await writeConfig.apply(contextOn(files));
      expect(files.contents[configPath], contains('ALERT_RECIPIENTS="oncall@example.com"'));
    });

    test('an answer that equals the template is not written and is not missing either', () async {
      // DEPLOY_ENV reads "prod" in the template and "prod" is a stage an installation really runs.
      // Read as "still unset" forever, this key would keep the step from ever being satisfied.
      final FakeFiles files = tree(config: configExample);
      final StepContext context = contextOn(files, answers: answering(stage: 'prod'));

      await writeConfig.apply(context);
      expect(files.contents[configPath], contains('DEPLOY_ENV="prod"'));
      expect(await writeConfig.check(context), isA<Satisfied>());
    });

    test('an answer that reads like an illustration is still the operator\'s own value', () async {
      // The incident this closes: a blanket "contains example.com" test threw away a legitimate unit
      // apex because it read like the illustrations the template carries, and the installation came
      // up with no apex for its units at all. Nothing here recognises an illustration. A key is
      // filled from its answer, or it keeps what an operator wrote — and the two are told apart by
      // the value the TEMPLATE carries, which is the only thing that can be compared against.
      final FakeFiles files = tree(config: configExample);

      await writeConfig.apply(contextOn(files));

      expect(files.contents[configPath], contains('UNIT_APEX="example.com"'));
    });

    test('every line nobody was asked about is copied through untouched', () async {
      final FakeFiles files = tree();
      await writeConfig.apply(contextOn(files));

      expect(files.contents[configPath], contains('POD_CIDR="10.244.0.0/16"'));
      expect(files.contents[configPath], contains('# The mailbox certificate notices go to.'));
      expect(
        files.contents[configPath]?.split('\n').length,
        configExample.split('\n').length,
        reason: 'a key is filled at its own position, never appended',
      );
    });

    test('a second run finds nothing to do and writes nothing', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      await writeConfig.apply(context);
      final String once = files.contents[configPath] ?? '';
      files.written.clear();

      expect(await writeConfig.check(context), isA<Satisfied>());
      expect(files.written, isEmpty);
      expect(files.contents[configPath], once);
    });

    test('a template that does not declare a key is refused, naming the key', () async {
      // `sed` exited zero whether or not it matched, so a key the template does not carry was
      // reported as filled while the file kept nothing at all.
      final FakeFiles files = FakeFiles(<String, String>{
        configTemplate: configExample.replaceAll('CATALOG_REPO=""\n', ''),
      });

      final CheckResult answer = await writeConfig.check(contextOn(files));
      expect((answer as Blocked).reason, contains('CATALOG_REPO'));
      expect(files.written, isEmpty);
    });

    test('a branch carrying no template at all is refused rather than guessed at', () async {
      final CheckResult answer = await writeConfig.check(contextOn(FakeFiles()));
      expect((answer as Blocked).reason, contains('config.example'));
    });

    test('an answer holding a double quote is refused, never mangled into the file', () async {
      final FakeFiles files = tree();
      final CheckResult answer = await writeConfig.check(
        contextOn(files, answers: answering(letsencryptEmail: 'certs"@example.com')),
      );
      expect((answer as Blocked).reason, contains('LETSENCRYPT_EMAIL'));
    });

    test('taking it back removes a config this run created', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      // Capture, apply, undo — the engine's own order, so what the undo is handed is what the
      // capture actually read rather than a value this test chose to make its assertion come out.
      final String? before = await writeConfig.capture(context);
      await writeConfig.apply(context);
      await writeConfig.undo(context, before);
      expect(files.contents.containsKey(configPath), isFalse);
    });

    test('taking it back leaves a config that was already there, minus this run', () async {
      final FakeFiles files = tree(
        config: configExample.replaceAll(
          'ALERT_RECIPIENTS=""',
          'ALERT_RECIPIENTS="oncall@example.com"',
        ),
      );
      final StepContext context = contextOn(files);

      final String? before = await writeConfig.capture(context);
      await writeConfig.apply(context);
      await writeConfig.undo(context, before);

      expect(files.contents.containsKey(configPath), isTrue);
      expect(files.contents[configPath], contains('ALERT_RECIPIENTS="oncall@example.com"'));
      expect(files.contents[configPath], contains('LETSENCRYPT_EMAIL="user@example.com"'));
    });
  });

  group('the credentials file the Vault seed reads', () {
    test('a machine with no credentials gets them, at 0600', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      await writeSecrets.apply(context);

      expect(files.contents[secretsPath], contains('GITOPS_REPO_PAT="writer-credential-0001"'));
      expect(files.modes[secretsPath], 0x180, reason: 'every value in it is a credential');
      expect(await writeSecrets.check(context), isA<Satisfied>());
    });

    test('a value a later phase wrote back survives a re-run', () async {
      // The incident this exists for: rewriting the file from the template took the root token and
      // the five unseal keys of a running Vault with it, and nothing anywhere else holds them.
      final FakeFiles files = tree(
        secrets: secretsExample.replaceAll(
          'VAULT_ROOT_TOKEN=""',
          'VAULT_ROOT_TOKEN="the-only-way-into-a-sealed-vault"',
        ),
      );

      await writeSecrets.apply(contextOn(files));
      expect(
        files.contents[secretsPath],
        contains('VAULT_ROOT_TOKEN="the-only-way-into-a-sealed-vault"'),
      );
    });

    test('a credential rotated by hand is left exactly as it is', () async {
      final FakeFiles files = tree(
        secrets: secretsExample.replaceAll(
          'CLOUDFLARE_API_TOKEN=""',
          'CLOUDFLARE_API_TOKEN="rotated-by-hand-0002"',
        ),
      );
      final StepContext context = contextOn(files);

      await writeSecrets.apply(context);
      expect(files.contents[secretsPath], contains('CLOUDFLARE_API_TOKEN="rotated-by-hand-0002"'));
      expect(files.contents[secretsPath], contains('GITOPS_REPO_PAT="writer-credential-0001"'));
      expect(await writeSecrets.check(context), isA<Satisfied>());
    });

    test('a second run finds nothing to do and writes nothing', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      await writeSecrets.apply(context);
      final String once = files.contents[secretsPath] ?? '';
      files.written.clear();

      expect(await writeSecrets.check(context), isA<Satisfied>());
      expect(files.written, isEmpty);
      expect(files.contents[secretsPath], once);
    });

    test('a plan names the keys it would fill and carries no credential', () async {
      // A plan is read out of the run record, which an operator reads without elevated rights and
      // pastes into a message when something has gone wrong.
      final StepPlan plan = await writeSecrets.plan(contextOn(tree()));
      final DiffPlan diff = plan as DiffPlan;

      expect(diff.after, contains('GITOPS_REPO_PAT=${Redactor.marker}'));
      expect(diff.after, isNot(contains('writer-credential-0001')));
      expect(diff.after, isNot(contains('storage-credential-0001')));
      // The two that name a machine and an account on it are not credentials, and hiding them would
      // make the plan unreadable for no gain.
      expect(diff.after, contains('STORAGE_BOX_HOST=u000000.your-storagebox.de'));
    });

    test('a cluster that does not carry the build plane is not asked for its four', () async {
      final FakeFiles files = tree();
      final Arguments elsewhere = answering(
        buildPlane: 'm0.example.com',
        without: const <String, Object>{
          'registry_dockerhub_user': '',
          'registry_dockerhub_token': '',
          'build_hostyour_cloud_repo_pat': '',
          'build_catalog_repo_pat': '',
        },
      );
      final StepContext context = contextOn(files, answers: elsewhere);

      await writeSecrets.apply(context);

      expect(files.contents[secretsPath], contains('GITOPS_REPO_PAT="writer-credential-0001"'));
      expect(files.contents[secretsPath], contains('BUILD_CATALOG_REPO_PAT=""'));
      expect(await writeSecrets.check(context), isA<Satisfied>());
    });

    test('a cluster that does carry it is refused while one of the four is missing', () async {
      final FakeFiles files = tree();
      final CheckResult answer = await writeSecrets.check(
        contextOn(
          files,
          answers: answering(without: const <String, Object>{'build_catalog_repo_pat': ''}),
        ),
      );

      final String reason = (answer as Blocked).reason;
      expect(reason, contains('build_catalog_repo_pat'));
      expect(reason, contains('build plane'));
      expect(files.written, isEmpty);
    });

    test('a template that does not declare a key is refused, naming the key', () async {
      final FakeFiles files = FakeFiles(<String, String>{
        secretsTemplate: secretsExample.replaceAll('STORAGE_BOX_HOST=""\n', ''),
      });

      final CheckResult answer = await writeSecrets.check(contextOn(files));
      expect((answer as Blocked).reason, contains('STORAGE_BOX_HOST'));
      expect(files.written, isEmpty);
    });

    test('taking it back leaves no credential on a machine whose install was abandoned', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      final String? before = await writeSecrets.capture(context);
      await writeSecrets.apply(context);
      await writeSecrets.undo(context, before);
      expect(files.contents.containsKey(secretsPath), isFalse);
    });

    test('taking it back keeps what a later phase had already written back', () async {
      final FakeFiles files = tree(
        secrets: secretsExample.replaceAll(
          'VAULT_ROOT_TOKEN=""',
          'VAULT_ROOT_TOKEN="the-only-way-into-a-sealed-vault"',
        ),
      );
      final StepContext context = contextOn(files);

      final String? before = await writeSecrets.capture(context);
      await writeSecrets.apply(context);
      await writeSecrets.undo(context, before);

      expect(files.contents.containsKey(secretsPath), isTrue);
      expect(
        files.contents[secretsPath],
        contains('VAULT_ROOT_TOKEN="the-only-way-into-a-sealed-vault"'),
      );
      expect(files.contents[secretsPath], isNot(contains('writer-credential-0001')));
    });
  });

  group('the mail-DNS configuration the publisher reads', () {
    const String mailDnsPath = '$repository/configs/mail-dns.dev.conf';
    const WriteStageMailDns step = WriteStageMailDns(repository: repository);

    test('a branch without it gets it, carrying the row that changes nothing', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      // The row is the one the publisher synthesises when it finds no file at all, so what would
      // be published is the same before and after this step. What changes is that an operator
      // adding a second sender apex has somewhere to add it.
      expect(files.contents[mailDnsPath], contains('"||auto|||||"'));
      expect(files.contents[mailDnsPath], contains('mail-dns.conf.example'));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a file the operator has added rows to is NOT rewritten', () async {
      // The rewrite this step exists not to perform. Its extra rows are the whole value of the
      // file, they are nowhere else, and a step comparing content against what it writes would
      // read them as a difference to correct.
      const String operators =
          'MAIL_DNS_DOMAINS=(\n'
          '"||auto|||||"\n'
          '"shop.example.com||auto|||||"\n'
          ')\n';
      final FakeFiles files = tree()..contents[mailDnsPath] = operators;
      final StepContext context = contextOn(files);

      expect(await step.check(context), isA<Satisfied>());
      await step.apply(context);

      expect(files.contents[mailDnsPath], operators);
      expect(
        files.written,
        isEmpty,
        reason: 'a satisfied step that writes anyway is not satisfied',
      );
    });

    test('taking the run back removes only the file this run left', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files);
      final bool wasThere = await step.capture(context);
      await step.apply(context);

      await step.undo(context, wasThere);

      expect(files.contents.containsKey(mailDnsPath), isFalse);
    });

    test('taking it back leaves a file the operator has since changed', () async {
      // An undo runs while cleaning up after a failure — the worst moment to delete rows somebody
      // typed. The check keeps that rule on the way in and this keeps it on the way out.
      const String operators =
          'MAIL_DNS_DOMAINS=(\n'
          '"shop.example.com||auto|||||"\n'
          ')\n';
      final FakeFiles files = tree()..contents[mailDnsPath] = operators;
      final StepContext context = contextOn(files);

      await step.undo(context, await step.capture(context));

      expect(files.contents[mailDnsPath], operators);
    });

    test('it is named for the stage the run answered, not for a remembered one', () async {
      final FakeFiles files = tree();
      final StepContext context = contextOn(files, answers: answering(stage: 'prod'));

      await step.apply(context);

      expect(files.contents.containsKey('$repository/configs/mail-dns.prod.conf'), isTrue);
      expect(files.contents.containsKey(mailDnsPath), isFalse);
    });
  });
}

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
