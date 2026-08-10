// A test may read the real files; the rule that confines `dart:io` is about the shipped library.
import 'dart:io' show File;

import 'package:ansiwise_api/ansiwise_api.dart';
// The binding that grants the administrator group its cluster rights is the kubernetes plugin's
// step. What this file measures about it is the program's, and the program is this package's.
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:ansiwise_api/testing.dart';
import 'package:test/test.dart';

import 'composition.dart';

/// The identity provider, and the half of logging in that lives outside it.
///
/// Two properties decide this area. A cluster with no identity provider stands and must not turn a
/// run red; and the cluster's own trust in the one it has is six arguments in a file, one of which
/// reads correct and locks every operator out.
void main() {
  // The six plugins the shipped configuration turns on, composed the way the binary composes
  // them. Resolved once, because reading a file per test says nothing more than reading it once.
  late final Registry shipped;
  setUpAll(() async => shipped = await shippedRegistry());

  const String issuer = 'https://idp.m1.example.com/application/o/headlamp/';

  /// The issuer as the PROGRAM writes it, with both its slots still in place, and the client it
  /// names.
  ///
  /// Written out here rather than read off a step, because the gate carries no default for either
  /// any more: which client this platform issues tokens for, and what shape the address has, are
  /// this deployment's decisions. They stand once in the program's defaults block and reach both
  /// rows from there, which is what the two agreement tests below now read.
  const String issuerRow = 'https://idp.<master-domain>/application/o/<client>/';
  const String client = 'headlamp';

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
        log: RecordingLogger(recorder: recorder, redactor: Redactor.none, step: name),
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
        ..answers('command -v microk8s', '/snap/bin/microk8s\n');
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
            program: ProgramResolver(shipped).resolve(
              loadProgram(
                File(programAt('deploy-gitops.yaml')).readAsStringSync(),
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
      expect(
        record.exitCode,
        0,
        reason: record.steps
            .where((StepRecord each) => each.verdict is Failed)
            .map((StepRecord each) => '${each.step}: ${(each.verdict as Failed).reason}')
            .join(' | '),
      );
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
        File(programAt('deploy-gitops.yaml')).readAsStringSync(),
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
        File(programAt('deploy-gitops.yaml')).readAsStringSync(),
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
      // The cluster never sees the group the identity provider issued, it sees that name with the
      // prefix in front of it. A binding written without the same prefix matches nobody: the
      // administrators get no rights and the run comes back green, which is the shape of failure
      // nothing else here would catch.
      final ResolvedProgram program = ProgramResolver(shipped).resolve(
        loadProgram(
          File(programAt('deploy-gitops.yaml')).readAsStringSync(),
          where: 'deploy-gitops.yaml',
        ),
      );
      final ResolvedStep flags = program.steps.firstWhere(
        (ResolvedStep step) => step.entry.step == const StepName('configure_kube_apiserver_oidc'),
      );
      final ResolvedStep binding = program.steps.firstWhere(
        (ResolvedStep step) => step.entry.step == const StepName('oidc_admins_binding'),
      );

      // Asked of the RESOLVED rows, so this holds however the program says it: written once as a
      // program-wide default, or written out on both rows. Written DIFFERENTLY on the two rows it
      // fails, which is the only thing that has to be true.
      //
      // The binding belongs to the kubernetes plugin, and that package carries no default for the
      // prefix: a tool package that guessed one would be guessing one product's choice.
      final ArgumentSpec declared = OidcAdminsBinding.arguments.firstWhere(
        (ArgumentSpec spec) => spec.name == 'groups_prefix',
      );
      expect(declared.defaultValue, isNull);
      expect(
        binding.entry.arguments.text('groups_prefix'),
        flags.entry.arguments.text('groups_prefix'),
      );
    });
  });

  group('the discovery document', () {
    /// The gate as the program builds it.
    const IdpDiscoveryReachable gate = IdpDiscoveryReachable(clientId: client, issuer: issuerRow);

    test('is a gate that verifies an earlier step', () {
      expect(
        gate.verifiesAnEarlierStep,
        isTrue,
        reason: 'the document does not exist until the identity provider is deployed',
      );
    });

    test('neither of its two values has a default, so the program has to state both', () {
      // The demotion this step exists on the product side for. A default here is the half of the
      // pair that stops being read the day the other row changes: the gate then measures an address
      // the cluster is not pointed at, and the run comes back green either way.
      for (final String name in <String>['client_id', 'issuer']) {
        final ArgumentSpec spec = IdpDiscoveryReachable.arguments.firstWhere(
          (ArgumentSpec each) => each.name == name,
        );
        expect(
          spec.defaultValue,
          isNull,
          reason: '$name is this deployment\'s choice, not a gate\'s',
        );
        expect(spec.required, isTrue, reason: 'a value nobody states is a value nobody chose');
      }
    });

    test('is read with a request that only reads', () async {
      final _Answering http = _Answering('{"authorization_endpoint": "https://example.com"}');
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: http,
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      expect(await gate.check(it.context), isA<Satisfied>());
      expect(http.sent.single.method, 'GET');
      expect(http.sent.single.observes, isTrue);
      expect(http.sent.single.url, endsWith('/${IdpDiscoveryReachable.discoveryPath}'));
    });

    test('names the address when something else is answering there', () async {
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: _Answering('<html>hello</html>'),
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      final CheckResult result = await gate.check(it.context);
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

      expect(gate.issuerUrlIn(it.context), issuer);
      expect(
        gate.issuerUrlIn(it.context),
        const ConfigureKubeApiserverOidc(
          clientId: client,
          usernameClaim: 'preferred_username',
          usernamePrefix: 'oidc:',
          groupsClaim: 'groups',
          groupsPrefix: '',
          argsPath: ConfigureKubeApiserverOidc.defaultPath,
          issuer: issuerRow,
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

      expect(gate.issuerUrlIn(it.context), issuer);
    });

    test('the client and the issuer both entries are given are the same words', () async {
      // Asked of the RESOLVED rows, so this holds however the program says it: written once as a
      // program-wide default, or written out on both rows. Written DIFFERENTLY on the two rows it
      // fails, which is the only thing that has to be true. A gate given its own address checks one
      // issuer while the cluster is pointed at another, and the run is green either way.
      final ResolvedProgram program = ProgramResolver(shipped).resolve(
        loadProgram(
          File(programAt('deploy-gitops.yaml')).readAsStringSync(),
          where: 'deploy-gitops.yaml',
        ),
      );
      Arguments given(String step) => program.steps
          .firstWhere((ResolvedStep each) => each.entry.step == StepName(step))
          .entry
          .arguments;

      expect(
        given('idp_discovery_reachable').text('client_id'),
        given('configure_kube_apiserver_oidc').text('client_id'),
      );
      expect(
        given('idp_discovery_reachable').text('issuer'),
        given('configure_kube_apiserver_oidc').text('issuer'),
      );
      // And they are the address with its slots still in it, not one installation's own: a program
      // file ships inside the binary to every installation and nothing rewrites it.
      expect(given('idp_discovery_reachable').text('issuer'), issuerRow);
    });

    test('an issuer row carrying a slot nothing fills is refused, not measured', () async {
      // A misspelled slot would otherwise stand inside the address this gate fetches, the request
      // would fail, and the message would blame the identity provider for an address nobody wrote.
      final ({StepContext context, MemoryRecorder recorder}) it = contextOf(
        shell: FakeShell(),
        files: FakeFiles(),
        http: FakeHttp(),
        step: 'idp_discovery_reachable',
        answers: onTheMaster,
      );

      final CheckResult result = await const IdpDiscoveryReachable(
        clientId: client,
        issuer: 'https://idp.<master-domian>/application/o/<client>/',
      ).check(it.context);
      expect(result, isA<Blocked>());
      expect((result as Blocked).reason, contains('<master-domian>'));
    });
  });
}

/// A network port that answers every request with the same document and keeps what was sent.
///
/// The table-driven fake answers by URL, which is no use to a gate whose whole question is what it
/// asked for: the address is composed inside the step, so a table keyed on it would have to repeat
/// the composition and would then agree with the step by construction. This one answers whatever is
/// asked and records the request, so the address and the method are read off what actually went out.
final class _Answering implements Http {
  /// Answers every request with [body].
  _Answering(this.body);

  /// What every request is answered with.
  final String body;

  /// Every request that was sent, in the order it went out.
  final List<HttpRequest> sent = <HttpRequest>[];

  @override
  Future<HttpAnswer> send(HttpRequest request) async {
    sent.add(request);
    return HttpAnswer(
      status: 200,
      body: body,
      headers: const <String, String>{},
      elapsed: Duration.zero,
    );
  }
}
