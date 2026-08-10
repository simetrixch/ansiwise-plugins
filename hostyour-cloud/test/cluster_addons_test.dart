import 'package:ansiwise_api/ansiwise_api.dart';
// How the cluster client is invoked belongs to the kubernetes plugin, which knows the tool and no
// installation's way of wrapping it.
import 'package:ansiwise_kubernetes/ansiwise_kubernetes.dart';
// Where the profile stands and what its keys are called is stated by the program, and the type that
// carries those names belongs to the secret store's plugin — which knows the tool and no layout.
import 'package:ansiwise_vault/ansiwise_vault.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The addons this platform switches on and off, and who the API server accepts.
void main() {
  const StepName under = StepName('under_test');

  String status({required List<String> on, required List<String> off}) {
    final StringBuffer written = StringBuffer()
      ..writeln('microk8s is running')
      ..writeln('addons:')
      ..writeln('  enabled:');
    for (final String addon in on) {
      written.writeln('    $addon  # (core) an addon');
    }
    written.writeln('  disabled:');
    for (final String addon in off) {
      written.writeln('    $addon  # (core) an addon');
    }
    return written.toString();
  }

  group('reading which addons are on', () {
    test('only the section listing what is on answers', () {
      // A search of the whole output finds an addon in the list of what is OFF and reports it as on.
      final Set<String> on = EnableAddons.readEnabled(
        status(on: <String>['dns', 'rbac'], off: <String>['registry', 'gpu']),
      );
      expect(on, <String>{'dns', 'rbac'});
      expect(on, isNot(contains('registry')));
    });

    test('a status that lists nothing as on answers with nothing', () {
      expect(EnableAddons.readEnabled('microk8s is not running\n'), isEmpty);
    });
  });

  group('switching the addons on', () {
    test('they go on in the order the program wrote them', () async {
      // Access control is first on purpose: until it is on, every access rule applied afterwards is
      // accepted and enforces nothing.
      final ClusterMachine machine = ClusterMachine();
      final List<String> on = <String>[];
      machine.shell.answers('microk8s status', status(on: on, off: <String>['registry']));
      for (final String addon in <String>['rbac', 'dns', 'ingress']) {
        machine.shell.changes('microk8s enable $addon', () {
          on.add(addon);
          machine.shell.answers('microk8s status', status(on: on, off: <String>['registry']));
        });
      }

      const EnableAddons step = EnableAddons(
        addons: <String>['rbac', 'dns', 'ingress'],
        dnsUpstreamServers: <String>[],
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.changing, <String>[
        'microk8s enable rbac',
        'microk8s enable dns',
        'microk8s enable ingress',
      ]);
    });

    test('an addon that is already on is not switched on again', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>['rbac'], off: <String>[]));

      const EnableAddons step = EnableAddons(
        addons: <String>['rbac'],
        dnsUpstreamServers: <String>[],
      );
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the name servers are given only on the first switch-on of the name addon', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>[], off: <String>['dns']));

      const EnableAddons step = EnableAddons(
        addons: <String>['dns'],
        dnsUpstreamServers: <String>['185.12.64.1', '185.12.64.2'],
      );
      await step.apply(machine.contextFor(under));
      expect(machine.changing, <String>['microk8s enable dns:185.12.64.1,185.12.64.2']);
    });
  });

  group('waiting for them to show up', () {
    const WaitForAddonsEnabled step = WaitForAddonsEnabled(
      addons: <String>['rbac', 'ingress'],
      timeoutSeconds: 30,
      intervalSeconds: 5,
    );

    test('an addon that is listed as off is not read as on', () async {
      // The reason this wait is not a command and an answer: every addon it is waiting for stands in
      // the list of what is OFF at the moment it starts looking, so a reading of the whole output
      // would answer yes straight away.
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>['rbac'], off: <String>['ingress']));

      expect(await step.check(machine.contextFor(under)), isA<Ready>());
    });

    test('a wait that runs out names the addons it was waiting for', () async {
      // What it costs the run is the program row's policy: the addon was asked for and has not
      // appeared, and the steps after it notice by themselves if it really did not arrive.
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>['rbac'], off: <String>['ingress']));

      await expectLater(
        step.apply(machine.contextFor(under)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.waitingFor,
            'what it waited for',
            contains('ingress'),
          ),
        ),
      );
      expect(machine.clock.elapsed.inSeconds, greaterThanOrEqualTo(30));
    });

    test('an addon that shows up while it is waiting ends the wait', () async {
      final ClusterMachine machine = ClusterMachine();
      int looks = 0;
      machine.shell
        ..answers('microk8s status', status(on: <String>['rbac'], off: <String>['ingress']))
        ..changes('microk8s status', () {
          looks++;
          if (looks >= 3) {
            machine.shell.answers(
              'microk8s status',
              status(on: <String>['rbac', 'ingress'], off: <String>[]),
            );
          }
        });

      await step.apply(machine.contextFor(under));
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a dry run says what it would wait for instead of waiting', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>[], off: <String>['rbac']));

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains('would wait up to 30s'));
      expect(plan.summary, contains('ingress'));
      expect(machine.clock.elapsed, Duration.zero);
    });
  });

  group('switching the addons off', () {
    test('the one that comes on by itself is switched off', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('microk8s status', status(on: <String>['rbac', 'registry'], off: <String>[]))
        ..changes('microk8s disable registry', () {
          machine.shell.answers(
            'microk8s status',
            status(on: <String>['rbac'], off: <String>['registry']),
          );
        });

      const DisableAddons step = DisableAddons(addons: <String>['registry']);
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('an addon that is already off is skipped', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('microk8s status', status(on: <String>['rbac'], off: <String>['registry']));

      const DisableAddons step = DisableAddons(addons: <String>['registry']);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a program that declares none is a step with nothing to do, not an error', () async {
      const DisableAddons step = DisableAddons(addons: <String>[]);
      expect(await step.check(ClusterMachine().contextFor(under)), isA<Satisfied>());
    });
  });

  group('who the API server accepts', () {
    const String argsPath = ConfigureKubeApiserverOidc.defaultPath;

    test('the claim carrying the user name is never the mail address', () async {
      // The API server refuses a token whose user-name claim is that one unless the token also says
      // the address was verified, which the identity provider does not say for the first
      // administrator or for any account made in the interface.
      const ConfigureKubeApiserverOidc byEmail = ConfigureKubeApiserverOidc(
        clientId: 'headlamp',
        usernameClaim: 'email',
        usernamePrefix: 'oidc:',
        groupsClaim: 'groups',
        groupsPrefix: '',
        argsPath: argsPath,
      );
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '';
      final CheckResult answer = await byEmail.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('preferred_username'));
    });

    test('the six flags are written and the service that reads them restarted', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[argsPath] = '--allow-privileged=true\n';

      final StepContext context = machine.contextFor(under);
      expect(await apiserverOidc.check(context), isA<Ready>());
      await apiserverOidc.apply(context);

      final String written = machine.files.contents[argsPath]!;
      expect(written, contains('--allow-privileged=true'));
      for (final MapEntry<String, String> flag in apiserverOidc.flagsIn(context).entries) {
        expect(written, contains('${flag.key}=${flag.value}'));
      }
      expect(await apiserverOidc.check(context), isA<Satisfied>());
      expect(machine.changing, contains('snap restart $microk8sKubelite'));
    });

    test('a second run writes nothing and restarts nothing', () async {
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = machine.contextFor(under);
      machine.files.contents[argsPath] = ConfigureKubeApiserverOidc.withFlags(
        '',
        apiserverOidc.flagsIn(context),
      );
      expect(await apiserverOidc.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
      expect(machine.changing, isEmpty);
    });
  });

  group('a cluster with no identity provider of its own', () {
    const String argsPath = ConfigureKubeApiserverOidc.defaultPath;
    const String repository = '/srv/hostyour-cloud';
    const String profilePath = '$repository/cluster/profile.yaml';

    /// A context whose run says what this cluster is.
    StepContext asRole(ClusterMachine machine, String role) =>
        machine.contextFor(under, Arguments.none, clusterAnswering(<String, Object>{'role': role}));

    // Where this platform's profile stands and what its keys are called. The secret store's plugin
    // carries no layout of its own, so this is stated here the way the program file states it —
    // and a test that named other keys would measure a file no installation writes.
    const VaultLayout layout = VaultLayout(
      profile: 'cluster/profile.yaml',
      urlKey: 'global.vaultUrl',
      nameKey: 'global.clusterName',
      authPathKey: 'global.vaultKubernetesAuthPath',
      credentials: 'secrets/vault-<stage>.txt',
    );

    // The words this platform's cluster client is invoked with. The kubernetes plugin defaults to a
    // plain kubectl on the path, which is the only invocation kubectl itself defines — a client that
    // lives behind a wrapping command is this installation's arrangement, so the row states it and
    // the fixture below scripts the same words.
    const Kubectl kubectl = Kubectl(<String>['microk8s', 'kubectl']);

    const ConfigureSlaveApiserverOidcTrust trust = ConfigureSlaveApiserverOidcTrust(
      repository: repository,
      clientId: 'headlamp',
      adminGroup: 'authentik Admins',
      bindingName: 'authentik-admins-cluster-admin',
      stateDirectory: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
      argsPath: argsPath,
      layout: layout,
      kubectl: kubectl,
    );

    test('a cluster that deploys the identity provider does nothing here', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[profilePath] = 'global:\n  vaultUrl: https://vault.m1.example.com\n';
      expect(await trust.check(asRole(machine, 'master')), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
    });

    test('a profile carrying no address is refused, not passed over', () async {
      // BLOCKED AND NOT SATISFIED. A profile with no address under the name this run was told to
      // look under is a question nothing answered, not "the stamp has not run yet". Reported as
      // satisfied, the run came back green with a slave whose API server accepts no token from the
      // identity provider — and the message blamed a stamp that had already run.
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[profilePath] = 'global:\n  domain: example.invalid\n';
      final CheckResult answer = await trust.check(asRole(machine, 'slave'));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('vaultUrl'));
    });

    test('the address is derived from the one value the role stamp writes', () async {
      // Derived from where the secret store answers, and never read from a key of its own: the two
      // follow the same installation, and a second key would be a second thing to keep in step.
      // The profile is not parsed here — one reader does that for the whole family, so where the
      // file stands and what its keys are called is a program row's to say in one place.
      expect(
        trust.issuerUrlFrom('https://vault.m1.example.com'),
        'https://idp.m1.example.com/application/o/headlamp/',
      );
      expect(
        trust.issuerUrlFrom(null),
        isNull,
        reason: 'a profile that named no address derives nothing',
      );
    });

    test('an issuer row carrying a slot nothing fills is refused, not sent', () async {
      // The issuer's shape is the row's to say, and its two slots are the only names the run
      // fills. A misspelled one would otherwise stand in the API server's own arguments, and every
      // login would be refused with a message about the token.
      const ConfigureSlaveApiserverOidcTrust misspelled = ConfigureSlaveApiserverOidcTrust(
        repository: repository,
        clientId: 'headlamp',
        adminGroup: 'authentik Admins',
        bindingName: 'authentik-admins-cluster-admin',
        stateDirectory: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
        argsPath: argsPath,
        issuer: 'https://idp.<master-domian>/application/o/<client>/',
        layout: layout,
        kubectl: kubectl,
      );
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[profilePath] = 'global:\n  vaultUrl: https://vault.m1.example.com\n';
      final CheckResult answer = await misspelled.check(asRole(machine, 'slave'));
      expect(answer, isA<Blocked>());
      expect((answer as Blocked).reason, contains('<master-domian>'));
    });

    test('the flags and the rule granting the administrators go on together', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents
        ..[profilePath] = 'global:\n  vaultUrl: https://vault.m1.example.com\n'
        ..[argsPath] = '';
      machine.shell
        ..fails(
          'microk8s kubectl get clusterrolebinding authentik-admins-cluster-admin -o '
          'jsonpath={.metadata.name}',
        )
        ..changes(
          'microk8s kubectl apply -f '
          '${ConfigureSlaveApiserverOidcTrust.defaultStateDirectory}/'
          'authentik-admins-cluster-admin.yaml',
          () => machine.shell.answers(
            'microk8s kubectl get clusterrolebinding authentik-admins-cluster-admin -o '
                'jsonpath={.metadata.name}',
            'authentik-admins-cluster-admin',
          ),
        );

      const ConfigureSlaveApiserverOidcTrust step = trust;
      final StepContext context = asRole(machine, 'slave');

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(
        machine.files.contents[argsPath],
        contains('--oidc-issuer-url=https://idp.m1.example.com/application/o/headlamp/'),
      );
      expect(machine.files.contents[step.manifestPath], contains('name: "authentik Admins"'));
    });
  });
}
