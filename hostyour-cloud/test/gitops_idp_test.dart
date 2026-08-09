// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'gitops_vault_test.dart' show ScriptedHttp, answer;

/// The identity provider, and the half of logging in that lives outside it.
///
/// Two properties decide this area. A cluster with no identity provider stands and must not turn a
/// run red; and the cluster's own trust in the one it has is six arguments in a file, one of which
/// reads correct and locks every operator out.
void main() {
  const String issuer = 'https://idp.m1.example.com/application/o/headlamp/';

  /// What a cluster holding the master part answers, which is what the issuer is composed from.
  const Arguments onTheMaster = Arguments(<String, Object>{
    'role': 'master',
    'fqdn': 'm1.example.com',
    'master': '',
  });

  ({StepContext context, MemoryRecorder recorder}) contextOf({
    required FakeShell shell,
    required FakeFiles files,
    required Http http,
    String step = 'apiserver_oidc_flags',
    Arguments answers = Arguments.none,
  }) {
    final FakeClock clock = FakeClock();
    final MemoryRecorder recorder = MemoryRecorder(clock);
    final StepName name = StepName(step);
    return (
      context: StepContext(
        shell: RecordingShell(shell, recorder: recorder, redactor: Redactor.none, step: name),
        files: RecordingFiles(files, recorder: recorder, step: name),
        http: RecordingHttp(http, recorder: recorder, redactor: Redactor.none, step: name),
        clock: clock,
        entropy: FakeEntropy(),
        log: RecordingLog(recorder: recorder, redactor: Redactor.none, step: name),
        step: name,
        arguments: Arguments.none,
        answers: answers,
        facts: Facts.none,
      ),
      recorder: recorder,
    );
  }

  group('an installation with no identity provider', () {
    test('stands, and the run stays green', () async {
      final FakeClock clock = FakeClock();
      final MemoryRecorder recorder = MemoryRecorder(clock);
      // The head gate asks for the two tools this program is made of, whatever the run turns out to
      // have to do. A machine that did not answer would stop there, and this test would then be red
      // for a reason that has nothing to do with the identity provider.
      final FakeShell shell = FakeShell()
        ..answers('command -v helm', '/usr/local/bin/helm\n')
        ..answers('command -v kubectl', '/usr/local/bin/kubectl\n');
      final FakeFiles files = FakeFiles(<String, String>{
        '/srv/hostyour-cloud/configs/config.dev': 'ENABLE_IDP=false\n',
      });

      final RunRecord record =
          await Runner(
            machine: Machine(
              shell: shell,
              files: files,
              http: FakeHttp(),
              clock: clock,
              entropy: FakeEntropy(),
            ),
            recorder: recorder,
            redactor: Redactor.none,
          ).run(
            program: const ProgramResolver(executionRegistry).resolve(
              loadProgram(
                File('programs/deploy-gitops.yaml').readAsStringSync(),
                where: 'deploy-gitops.yaml',
              ),
            ),
            mode: Mode.run,
            header: RunRecord(
              id: const RunId('20260807T120000Z-3'),
              program: const ProgramName('deploy-gitops'),
              mode: Mode.run,
              argv: const <String>['ansiwise', 'deploy-gitops'],
              start: clock.now(),
              stage: const Stage('dev'),
              role: const Role('master'),
              fqdn: const Fqdn('m1.example.com'),
              commit: 'abc1234',
              fingerprint: 'f',
            ),
          );

      // Skipped and not failed. A component nobody asked for is an answer about this installation,
      // and the run says which condition gave it.
      expect(record.exitCode, 0);
      expect(record.issues, isEmpty);
      final StepRecord flags = record.steps.firstWhere(
        (StepRecord step) => step.step == const StepName('configure_kube_apiserver_oidc'),
      );
      expect(flags.verdict, isA<Skipped>());
      expect((flags.verdict as Skipped).predicate, 'idp_enabled');

      expect(
        files.written,
        isEmpty,
        reason: 'a cluster with no identity provider is not wired to trust one',
      );
    });

    test('and the browser login into the secret store is skipped with it', () {
      // The wiring that lets a browser log into the secret store is gated on BOTH conditions: it
      // needs a store to configure and something to log in through, and without the second it is
      // not half applied — it is not applied.
      final Program program = loadProgram(
        File('programs/deploy-gitops.yaml').readAsStringSync(),
        where: 'deploy-gitops.yaml',
      );
      final List<ProgramStep> forBrowsers = program.steps
          .where((ProgramStep step) => step.when.contains(const PredicateName('idp_enabled')))
          .toList();

      expect(
        forBrowsers.map((ProgramStep step) => step.step.value),
        containsAll(<String>['vault_auth_method', 'vault_policy', 'vault_auth_role']),
      );
      for (final ProgramStep step in forBrowsers) {
        if (step.step == const StepName('vault_policy')) {
          expect(step.arguments.text('name'), 'admin');
        }
        if (step.step == const StepName('vault_auth_role')) {
          expect(step.arguments.text('mount'), 'oidc');
        }
        if (step.step == const StepName('vault_auth_method')) {
          expect(step.when, contains(const PredicateName('vault_enabled')));
        }
      }
    });
  });

  group('the cluster\'s trust in it', () {
    test('the claim that works is the one the program leaves to its default', () {
      // The wiring of the API server's own arguments belongs to the cluster area and is tested
      // there. What this program owns is naming it, and not overriding the one value that reads
      // correct and locks every operator out: the API server refuses a token whose user-name claim
      // is the mail address unless the token also says the address was verified, which the identity
      // provider does not say for any account a fresh installation has.
      final Program program = loadProgram(
        File('programs/deploy-gitops.yaml').readAsStringSync(),
        where: 'deploy-gitops.yaml',
      );
      final ProgramStep entry = program.steps.firstWhere(
        (ProgramStep step) => step.step == const StepName('configure_kube_apiserver_oidc'),
      );
      expect(entry.when, contains(const PredicateName('idp_enabled')));
      expect(entry.arguments.optionalText('username_claim'), isNull);

      final ArgumentSpec claim = ConfigureKubeApiserverOidc.arguments.firstWhere(
        (ArgumentSpec spec) => spec.name == 'username_claim',
      );
      expect(claim.defaultValue, 'preferred_username');
    });

    test('the prefix the arguments add and the prefix the binding matches are the same', () {
      // Set together on purpose. The cluster never sees the group the identity provider issued, it
      // sees that name with the prefix in front of it, and a binding written without it matches
      // nobody.
      final Program program = loadProgram(
        File('programs/deploy-gitops.yaml').readAsStringSync(),
        where: 'deploy-gitops.yaml',
      );
      final ProgramStep flags = program.steps.firstWhere(
        (ProgramStep step) => step.step == const StepName('configure_kube_apiserver_oidc'),
      );
      final ProgramStep binding = program.steps.firstWhere(
        (ProgramStep step) => step.step == const StepName('oidc_admins_binding'),
      );
      final ArgumentSpec declared = OidcAdminsBinding.arguments.firstWhere(
        (ArgumentSpec spec) => spec.name == 'groups_prefix',
      );
      expect(
        flags.arguments.text('groups_prefix'),
        binding.arguments.optionalText('groups_prefix') ?? declared.defaultValue,
      );
    });

    test('the binding carries the prefix the arguments add', () async {
      final FakeShell shell = FakeShell()
        ..fails('kubectl get clusterrolebinding oidc-platform-admins -o json');
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: shell,
        files: FakeFiles(),
        http: FakeHttp(),
        step: 'oidc_admins_binding',
      );

      const OidcAdminsBinding step = OidcAdminsBinding(
        name: 'oidc-platform-admins',
        group: 'authentik Admins',
        groupsPrefix: 'oidc:',
        clusterRole: 'cluster-admin',
      );
      expect(await step.check(it.context), isA<Ready>());
      await step.apply(it.context);

      expect(
        shell.ran.join('\n'),
        contains('--group=oidc:authentik Admins'),
        reason:
            'the cluster never sees the group the identity provider issued, only the prefixed '
            'name — a binding written without the prefix matches nobody',
      );
    });
  });

  group('the discovery document', () {
    test('is a gate that verifies an earlier step', () {
      const IdpDiscoveryReachable step = IdpDiscoveryReachable(clientId: 'headlamp');
      expect(
        step.verifiesAnEarlierStep,
        isTrue,
        reason: 'the document does not exist until the identity provider is deployed',
      );
    });

    test('is read with a request that only reads', () async {
      final ScriptedHttp http = ScriptedHttp(
        (HttpRequest request, int nth) =>
            answer('{"authorization_endpoint": "https://example.com"}'),
      );
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: http,
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      expect(
        await const IdpDiscoveryReachable(clientId: 'headlamp').check(it.context),
        isA<Satisfied>(),
      );
      expect(http.sent.single.method, 'GET');
      expect(http.sent.single.observes, isTrue);
      expect(http.sent.single.url, endsWith('/.well-known/openid-configuration'));
    });

    test('names the address when something else is answering there', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: ScriptedHttp((HttpRequest request, int nth) => answer('<html>hello</html>')),
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      final CheckResult result = await const IdpDiscoveryReachable(
        clientId: 'headlamp',
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('openid-configuration'));
    });

    test('measures the issuer the API server is pointed at, and never a second one', () async {
      // The two are the same address by construction and not by two people writing it twice: a gate
      // given its own address checks one issuer while the cluster is pointed at another, and the run
      // is green either way. What is left in the program file is the client, which is part of the
      // address — so the two entries have to name the same one.
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: FakeHttp(),
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      expect(const IdpDiscoveryReachable(clientId: 'headlamp').issuerUrlIn(it.context), issuer);
      expect(
        const IdpDiscoveryReachable(clientId: 'headlamp').issuerUrlIn(it.context),
        const ConfigureKubeApiserverOidc(
          clientId: 'headlamp',
          usernameClaim: 'preferred_username',
          usernamePrefix: 'oidc:',
          groupsClaim: 'groups',
          groupsPrefix: '',
          argsPath: ConfigureKubeApiserverOidc.defaultPath,
        ).issuerUrlIn(it.context),
      );
    });

    test('a slave measures the issuer of the cluster it belongs to', () {
      // The counter-probe for the composition: an issuer that came from an answer about THIS
      // cluster would pass every test above and point a slave at an identity provider that does not
      // stand there.
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: FakeHttp(),
        step: 'idp_discovery_reachable',
        answers: const Arguments(<String, Object>{
          'role': 'slave',
          'fqdn': 's1.example.com',
          'master': 'm1.example.com',
        }),
      );

      expect(const IdpDiscoveryReachable(clientId: 'headlamp').issuerUrlIn(it.context), issuer);
    });

    test('the client both entries name is the same word', () {
      final Program program = loadProgram(
        File('programs/deploy-gitops.yaml').readAsStringSync(),
        where: 'deploy-gitops.yaml',
      );
      final Object? fallback = IdpDiscoveryReachable.arguments
          .firstWhere((ArgumentSpec spec) => spec.name == 'client_id')
          .defaultValue;
      String clientOf(String step) {
        final ProgramStep entry = program.steps.firstWhere(
          (ProgramStep each) => each.step == StepName(step),
        );
        return entry.arguments.optionalText('client_id') ?? '$fallback';
      }

      expect(clientOf('idp_discovery_reachable'), clientOf('configure_kube_apiserver_oidc'));
    });
  });
}
