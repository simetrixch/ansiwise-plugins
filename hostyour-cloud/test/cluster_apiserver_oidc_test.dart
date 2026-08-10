import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// Who the API server accepts.
///
/// The addons this platform switches on and off moved to the machine plugin with the reading of the
/// snap's status, and what a cluster with no identity provider of its own needs is two rows of the
/// program now — the same flags this step writes, and the binding the kubernetes plugin applies.
/// What is left here is the one thing no tool decides: the shape of the address this platform's
/// identity provider issues at.
void main() {
  const StepName under = StepName('under_test');
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

  test('an issuer row carrying a slot nothing fills is refused, not sent', () async {
    // The issuer's shape is the row's to say, and its two slots are the only names the run fills. A
    // misspelled one would otherwise stand in the API server's own arguments, and every login would
    // be refused with a message about the token.
    const ConfigureKubeApiserverOidc misspelled = ConfigureKubeApiserverOidc(
      clientId: 'headlamp',
      usernameClaim: 'preferred_username',
      usernamePrefix: 'oidc:',
      groupsClaim: 'groups',
      groupsPrefix: '',
      argsPath: argsPath,
      issuer: 'https://idp.<master-domian>/application/o/<client>/',
    );
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[argsPath] = '';
    final CheckResult answer = await misspelled.check(machine.contextFor(under));
    expect((answer as Blocked).reason, contains('<master-domian>'));
  });

  test('a cluster that holds no master part is pointed at the one that does', () async {
    // The domain comes from the run's own answers: this cluster's own where it holds the master
    // part, and the cluster it names where it does not.
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[argsPath] = '';
    final StepContext slave = machine.contextFor(
      under,
      Arguments.none,
      clusterAnswering(<String, Object>{
        'role': 'slave',
        'fqdn': 's1.example.com',
        'master': 'm1.example.com',
      }),
    );
    expect(apiserverOidc.issuerUrlIn(slave), 'https://idp.m1.example.com/application/o/headlamp/');
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
}
