import 'dart:convert';

import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The mirror this cluster's public-registry pulls go through, and the states its credential can be
/// found in.
void main() {
  const StepName under = StepName('under_test');
  const String repository = '/srv/hostyour-cloud';
  const String stage = 'dev';
  const String thisCluster = 's1.example.com';
  const String buildPlane = 'm1.example.com';
  const String registryHost = 'zot.$buildPlane';
  const String profilePath = '$repository/cluster/profile.yaml';
  const String secretsPath = '$repository/secrets/secrets.$stage';
  const String credential = 'cHVsbC11c2VyOnNlY3JldA==';

  String profile({String host = registryHost}) =>
      'global:\n'
      '  vaultUrl: https://vault.$buildPlane\n'
      '  endpoints:\n'
      '    registry:\n'
      '      host: $host\n';

  String secrets({String? value, String newline = '\n'}) {
    final String written =
        value ??
        base64.encode(
          utf8.encode(
            jsonEncode(<String, Object>{
              'auths': <String, Object>{
                registryHost: <String, String>{'auth': credential},
              },
            }),
          ),
        );
    return <String>[
      '# the credentials this machine needs',
      'REGISTRY_PULL_DOCKERCONFIGJSON=$written',
      '',
    ].join(newline);
  }

  const PreflightDockerMirrorCredential preflight = PreflightDockerMirrorCredential(
    repository: repository,
  );

  const WriteContainerdDockerMirror mirror = WriteContainerdDockerMirror(
    repository: repository,
    certsDirectory: WriteContainerdDockerMirror.defaultCertsDirectory,
  );

  /// A run on a slave that pulls through the build plane's registry, which is the case these tests
  /// are written on: the three values the two steps read are answered, not constructed into them.
  Arguments answeredAs({String fqdn = thisCluster, String buildPlaneFqdn = buildPlane}) =>
      clusterAnswering(<String, Object>{
        'stage': stage,
        'fqdn': fqdn,
        'build_plane': buildPlaneFqdn,
      });

  ClusterMachine cluster({String? secretsFile, bool certsDirectory = true}) {
    final ClusterMachine machine = ClusterMachine();
    machine.files.contents[profilePath] = profile();
    if (secretsFile != null) {
      machine.files.contents[secretsPath] = secretsFile;
    }
    if (certsDirectory) {
      machine.files.directories.add(WriteContainerdDockerMirror.defaultCertsDirectory);
    }
    return machine;
  }

  group('the states the credential can be found in', () {
    test('a cluster that hosts the registry itself needs no mirror at all', () async {
      // At this point in its own install that registry does not exist, so this is a genuine no-op
      // rather than something that failed.
      expect(
        await preflight.check(
          cluster().contextFor(under, Arguments.none, answeredAs(fqdn: buildPlane)),
        ),
        isA<Satisfied>(),
      );
    });

    test('a registry address that cannot be read means there is no mirror to write', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.contents[profilePath] = 'global:\n  vaultUrl: https://vault.$buildPlane\n';
      expect(
        await preflight.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
    });

    test('no secrets file on the machine warns, writes no mirror and stays green', () async {
      // The unattended base install of a cluster runs before any secrets reach it. Failing here
      // would kill every one of them.
      final ClusterMachine machine = cluster();
      expect(
        await preflight.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(machine.said.join('\n'), contains(secretsPath));
      expect(machine.said.join('\n'), contains('run this program again'));

      final ClusterMachine writing = cluster();
      expect(
        await mirror.check(writing.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(writing.files.written, isEmpty);
    });

    test('a secrets file with the line endings of another operating system is refused', () async {
      // The character prints as nothing, so the failure surfaces far away as a rejected credential
      // for a value that looks perfectly correct.
      final ClusterMachine machine = cluster(secretsFile: secrets(newline: '\r\n'));
      final CheckResult answer = await preflight.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('line endings'));
    });

    test('a blank credential is refused by name', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets(value: ''));
      final CheckResult answer = await preflight.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('REGISTRY_PULL_DOCKERCONFIGJSON'));
      expect(answer.reason, contains('blank'));
    });

    test('the placeholder the example file ships is refused by name', () async {
      final ClusterMachine machine = cluster(
        secretsFile: secrets(
          value: '${PreflightDockerMirrorCredential.placeholderPrefix}/dev/null',
        ),
      );
      final CheckResult answer = await preflight.check(
        machine.contextFor(under, Arguments.none, answeredAs()),
      );
      expect((answer as Blocked).reason, contains('placeholder'));
    });

    test('a usable credential passes', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets());
      expect(
        await preflight.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
    });

    test('the same refusal is made again where the mirror is written', () async {
      // Running this program on its own keeps the guard that the step before the install carries.
      final ClusterMachine machine = cluster(secretsFile: secrets(value: ''));
      expect(
        await mirror.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Blocked>(),
      );
      expect(machine.files.written, isEmpty);
    });
  });

  group('the file the mirror is written into', () {
    test('the public registry stays in it as the fallback', () async {
      // With it, a mirror that is down makes a pull slower. Without it, the same mirror makes every
      // pull impossible.
      final ClusterMachine machine = cluster(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(
        machine.files.contents[mirror.path],
        contains('server = "${WriteContainerdDockerMirror.fallback}"'),
      );
    });

    test('the registry address comes from the profile and is never composed', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      final String written = machine.files.contents[mirror.path]!;
      expect(written, contains('[host."https://$registryHost"]'));
      expect(
        written,
        isNot(contains(thisCluster)),
        reason: 'nothing here composes the address out of any domain',
      );
    });

    test('it carries the credential and is readable by its owner alone', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets());
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(machine.files.contents[mirror.path], contains('authorization = "Basic $credential"'));
      expect(machine.files.modes[mirror.path], 0x180);
    });

    test('the credential reaches the file and nothing else', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets());
      final StepContext context = machine.contextFor(under, Arguments.none, answeredAs());
      await mirror.apply(context);
      final StepPlan plan = await mirror.plan(context);

      expect(machine.said.join('\n'), isNot(contains(credential)));
      expect(plan.summary, isNot(contains(credential)));
      expect((plan as DiffPlan).after, isNot(contains(credential)));
    });

    test('nothing out of the secrets file reaches this program beyond the credential', () async {
      // A secrets file that is run rather than read puts every value in it into everything the run
      // starts afterwards.
      final ClusterMachine machine = cluster(
        secretsFile: '${secrets()}SOME_OTHER_SECRET=must-not-travel\n',
      );
      await mirror.apply(machine.contextFor(under, Arguments.none, answeredAs()));
      expect(machine.files.contents[mirror.path], isNot(contains('must-not-travel')));
      expect(machine.said.join('\n'), isNot(contains('must-not-travel')));
    });

    test('a second run does not write it again, and nothing is restarted', () async {
      // The container runtime reads the file again on every pull.
      final ClusterMachine machine = cluster(secretsFile: secrets());
      final StepContext context = machine.contextFor(under, Arguments.none, answeredAs());

      expect(await mirror.check(context), isA<Ready>());
      await mirror.apply(context);
      expect(await mirror.check(context), isA<Satisfied>());
      expect(machine.files.written, hasLength(1));
      expect(machine.changing, isEmpty);
    });

    test('a machine whose runtime reads no such directory is warned and skipped', () async {
      final ClusterMachine machine = cluster(secretsFile: secrets(), certsDirectory: false);
      expect(
        await mirror.check(machine.contextFor(under, Arguments.none, answeredAs())),
        isA<Satisfied>(),
      );
      expect(machine.files.written, isEmpty);
      expect(machine.said.join('\n'), contains('rate-limited'));
    });
  });
}
