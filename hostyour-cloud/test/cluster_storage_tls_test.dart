import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// Where the volumes land, and the issuer every certificate on the cluster comes from.
void main() {
  const StepName under = StepName('under_test');
  const String storagePath = '/mnt/data';
  const String storageDirectory = '$storagePath/microk8s';

  /// A run on a machine with a separate filesystem, or on one without where both are empty.
  ///
  /// The two paths are answered rather than constructed into the steps: whether a machine has a
  /// separate filesystem, and where, is one machine's fact.
  StepContext withStorage(
    ClusterMachine machine, {
    String path = storagePath,
    String directory = storageDirectory,
  }) => machine.contextFor(
    under,
    Arguments.none,
    clusterAnswering(<String, Object>{'storage_path': path, 'storage_directory': directory}),
  );
  const String linkPath = LinkMicrok8sStoragePath.defaultPath;
  const String storageClasses =
      'microk8s kubectl get storageclass -o '
      r'jsonpath={range .items[*]}{.metadata.name}{" "}'
      r'{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}{"\n"}{end}';
  const String issuerReady =
      'microk8s kubectl get clusterissuer letsencrypt-prod -o '
      'jsonpath={.status.conditions[?(@.type=="Ready")].status}';
  const String issuerExists =
      'microk8s kubectl get clusterissuer letsencrypt-prod -o jsonpath={.metadata.name}';

  group('the data filesystem', () {
    test('a path that is an ordinary directory rather than a mount is refused', () async {
      // Everything the cluster writes through it would land on the machine's own filesystem, fill
      // it, and be missing from whatever the data filesystem is backed up by.
      final ClusterMachine machine = ClusterMachine();
      machine.files.directories.add(storagePath);
      machine.shell.fails('mountpoint -q $storagePath');

      const CheckStorageMount step = CheckStorageMount();
      final CheckResult answer = await step.check(withStorage(machine));
      expect((answer as Blocked).reason, contains('ordinary directory'));
    });

    test('a machine with no separate filesystem keeps the default and is not refused', () async {
      const CheckStorageMount step = CheckStorageMount();
      expect(
        await step.check(withStorage(ClusterMachine(), path: '', directory: '')),
        isA<Satisfied>(),
      );
    });

    test('a mounted path passes', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.files.directories.add(storagePath);
      const CheckStorageMount step = CheckStorageMount();
      expect(await step.check(withStorage(machine)), isA<Satisfied>());
    });
  });

  group('the directory every volume lives under', () {
    test('is made once, and a machine that has it is left exactly as it is', () async {
      final ClusterMachine machine = ClusterMachine();
      const CreateStorageDirectory step = CreateStorageDirectory(mode: 493);
      final StepContext context = withStorage(machine);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.modes[storageDirectory], 493);
    });

    test('it says what is lost, because removing it destroys every volume under it', () {
      const CreateStorageDirectory step = CreateStorageDirectory(mode: 493);
      expect(step.irreversibleReason, contains('destroys the data'));
    });
  });

  group('the link the volume provider writes through', () {
    LinkMicrok8sStoragePath link({bool force = false}) =>
        LinkMicrok8sStoragePath(microk8sStoragePath: linkPath, force: force);

    test('a real directory already there is moved aside before the link is made', () async {
      // The cluster may already have written volumes into it, and replacing it with a link would
      // leave that data with nothing pointing at it and no note of where it went.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..fails('test -L $linkPath')
        ..answers('test -d $linkPath', '');

      await link().apply(withStorage(machine));
      expect(machine.changing.first, startsWith('mv $linkPath $linkPath.orig.'));
      expect(machine.changing.last, 'ln -s $storageDirectory $linkPath');
      expect(machine.said.join('\n'), contains('is at $linkPath.orig.'));
    });

    test('a link already pointing at the right place is left alone', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '$storageDirectory\n');

      expect(await link().check(withStorage(machine)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test(
      'a link pointing somewhere else is left alone and the step still reports success',
      () async {
        // It is the only thing saying where this cluster's volumes are, and repointing it silently
        // would strand every one of them.
        final ClusterMachine machine = ClusterMachine();
        machine.shell
          ..answers('test -L $linkPath', '')
          ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

        expect(await link().check(withStorage(machine)), isA<Satisfied>());
        expect(machine.changing, isEmpty);
        expect(machine.said.join('\n'), contains('Set force to repoint it'));
      },
    );

    test('asked for by name, the wrong link is repointed', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('test -L $linkPath', '')
        ..answers('readlink -f $linkPath', '/srv/elsewhere\n');

      expect(await link(force: true).check(withStorage(machine)), isA<Ready>());
      await link(force: true).apply(withStorage(machine));
      expect(machine.changing, <String>['rm $linkPath', 'ln -s $storageDirectory $linkPath']);
    });

    test('a machine with no separate filesystem is not linked at all', () async {
      const LinkMicrok8sStoragePath none = LinkMicrok8sStoragePath(
        microk8sStoragePath: linkPath,
        force: false,
      );
      final ClusterMachine machine = ClusterMachine();
      expect(await none.check(withStorage(machine, path: '', directory: '')), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });
  });

  group('the class a claim gets when it names none', () {
    const SetDefaultStorageClass step = SetDefaultStorageClass(
      timeoutSeconds: 120,
      intervalSeconds: 5,
    );

    test(
      'the first class the addon produced is marked, and its name is never configured',
      () async {
        final ClusterMachine machine = ClusterMachine();
        machine.shell
          ..answers(storageClasses, 'microk8s-hostpath \n')
          ..changes(
            'microk8s kubectl patch storageclass microk8s-hostpath --type merge -p '
            '{"metadata":{"annotations":{"${SetDefaultStorageClass.annotation}":"true"}}}',
            () => machine.shell.answers(storageClasses, 'microk8s-hostpath true\n'),
          );

        final StepContext context = withStorage(machine);
        expect(await step.check(context), isA<Ready>());
        await step.apply(context);
        expect(await step.check(context), isA<Satisfied>());
      },
    );

    test('a class already marked is left alone', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers(storageClasses, 'microk8s-hostpath true\n');
      expect(await step.check(withStorage(machine)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a cluster with no class yet is waited for rather than left without a default', () async {
      // The legacy behaviour warned and moved on, which left a first install with no default class
      // until somebody came back and ran the whole thing a second time. This waits instead.
      final ClusterMachine machine = ClusterMachine();
      int looks = 0;
      machine.shell
        ..answers(storageClasses, '')
        ..changes(storageClasses, () {
          looks++;
          if (looks >= 3) {
            machine.shell.answers(storageClasses, 'microk8s-hostpath \n');
          }
        });

      await step.apply(withStorage(machine));
      expect(machine.changing.join('\n'), contains('patch storageclass microk8s-hostpath'));
      expect(machine.clock.elapsed.inSeconds, greaterThan(0));
    });

    test('a cluster that never produces one ends in a reported failure', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(storageClasses, '');
      await expectLater(step.apply(withStorage(machine)), throwsA(isA<WaitedTooLong>()));
    });
  });

  group('the certificate issuer', () {
    test('a freshly applied issuer with no status at all reports as not ready', () async {
      // A reader that expects the conditions to be there fails on the very state it is meant to
      // report.
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, '');
      expect(
        await RestartCertManagerAndReapplyClusterIssuer.isReady(
          withStorage(machine),
          const Kubectl(),
          'letsencrypt-prod',
        ),
        isFalse,
      );
    });

    test('the mailbox is the one this run answered, whatever it reads like', () async {
      // Nothing here recognises an illustration. The address used to stand in the program file and
      // was warned about when it ended in the domain the examples use; it is answered now, so a
      // rule of that kind would only refuse an operator whose own mailbox reads like one.
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = machine.contextFor(
        under,
        Arguments.none,
        clusterAnswering(<String, Object>{'letsencrypt_email': 'ops@example.com'}),
      );

      await clusterIssuer.apply(context);

      expect(machine.files.contents[clusterIssuer.path], contains('email: ops@example.com'));
    });

    test('the rendered manifest names the issuer, the authority and how it is answered', () async {
      final ClusterMachine machine = ClusterMachine();
      await clusterIssuer.apply(withStorage(machine));
      final String written = machine.files.contents[clusterIssuer.path]!;
      expect(written, contains('kind: ClusterIssuer'));
      expect(written, contains('name: letsencrypt-prod'));
      expect(written, contains('server: https://acme-v02.api.letsencrypt.org/directory'));
      expect(written, contains('ingressClassName: public'));
      expect(await clusterIssuer.check(withStorage(machine)), isA<Satisfied>());
    });

    test('the existing issuer is taken away only when that was asked for', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers(issuerExists, 'letsencrypt-prod');

      const DeleteExistingClusterIssuer left = DeleteExistingClusterIssuer(
        name: 'letsencrypt-prod',
        force: false,
      );
      expect(await left.check(withStorage(machine)), isA<Satisfied>());
      expect(machine.changing, isEmpty);

      const DeleteExistingClusterIssuer asked = DeleteExistingClusterIssuer(
        name: 'letsencrypt-prod',
        force: true,
      );
      expect(await asked.check(withStorage(machine)), isA<Ready>());
      expect(asked.irreversibleReason, contains('account key'));
    });
  });

  group('the one recovery an issuer that did not register gets', () {
    const RestartCertManagerAndReapplyClusterIssuer step =
        RestartCertManagerAndReapplyClusterIssuer(
          name: 'letsencrypt-prod',
          namespace: 'cert-manager',
          stateDirectory: ConfigureSlaveApiserverOidcTrust.defaultStateDirectory,
          settleSeconds: 15,
          waitSeconds: 60,
          intervalSeconds: 10,
        );

    test('an issuer that registered is left completely alone', () async {
      final ClusterMachine machine = ClusterMachine()..shell.answers(issuerReady, 'True');
      expect(await step.check(withStorage(machine)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('the recovery restarts the service and applies the issuer again, in that order', () async {
      // Polling longer does not converge: what it is stuck on is network state the certificate
      // service is holding from before the cluster's own network was finished.
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = withStorage(machine);
      machine.files.contents[step.manifestPath] = await clusterIssuer.manifestFor(context);
      machine.shell
        ..answers(issuerReady, '')
        ..changes('microk8s kubectl apply -f ${step.manifestPath}', () {
          machine.shell.answers(issuerReady, 'True');
        });

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      final List<String> ran = machine.changing;
      expect(ran.first, contains('rollout restart deployment/cert-manager'));
      expect(
        ran.indexWhere((String each) => each.contains('delete clusterissuer')),
        lessThan(ran.indexWhere((String each) => each.contains('apply -f'))),
      );
      expect(machine.clock.elapsed.inSeconds, greaterThanOrEqualTo(20));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the budget ends here, and what it means is reported', () async {
      final ClusterMachine machine = ClusterMachine();
      final StepContext context = withStorage(machine);
      machine.files.contents[step.manifestPath] = await clusterIssuer.manifestFor(context);
      machine.shell.answers(issuerReady, '');

      await expectLater(
        step.apply(withStorage(machine)),
        throwsA(
          isA<WaitedTooLong>().having(
            (WaitedTooLong failure) => failure.message,
            'message',
            contains('stuck rather than slow'),
          ),
        ),
      );
    });
  });
}
