import 'package:ansiwise_api/ansiwise_api.dart';
import 'package:hostyour_cloud/hostyour_cloud.dart';
import 'package:test/test.dart';

import 'cluster_fixture.dart';

/// The tools an operator uses on the machine, and the pins that make two machines the same.
void main() {
  const StepName under = StepName('under_test');

  group('the two things every tool download needs', () {
    const EnsureToolPrerequisites step = EnsureToolPrerequisites(
      packages: <String>['curl', 'unzip'],
    );

    test('the verdict comes from the commands, never from the package manager', () async {
      // Automatic updates hold the package lock for minutes after a machine boots, so an install
      // exits with a failure on a freshly provisioned machine that already carries both.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v curl', '/usr/bin/curl\n')
        ..answers('command -v unzip', '/usr/bin/unzip\n')
        ..fails('apt-get install --yes', exitCode: 100, stderr: 'could not get lock');

      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a machine missing one of them installs it and is judged again on the command', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v curl', '/usr/bin/curl\n')
        ..fails('command -v unzip')
        ..fails('apt-get install --yes unzip', exitCode: 100, stderr: 'could not get lock')
        ..changes('apt-get install --yes unzip', () {
          machine.shell.answers('command -v unzip', '/usr/bin/unzip\n');
        });

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(
        await step.check(context),
        isA<Satisfied>(),
        reason: 'the package manager reported a failure and the command is there',
      );
    });

    test('one gate up front rather than three failures further down', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.fails('command -v curl')
        ..shell.fails('command -v unzip');
      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect(plan.summary, contains('curl'));
      expect(plan.summary, contains('unzip'));
    });
  });

  group('the skip predicate, which differs by tool and must not be unified', () {
    test('a tool fetched at a pinned release skips on the version and not on being there', () async {
      // A binary that was on the machine before this platform existed would otherwise be left where
      // it is, held against the pin, and reported as wrong on every run with nothing able to fix it.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v yq', '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.40.0\n');

      const InstallYqCli step = InstallYqCli(version: 'v4.53.3', path: InstallYqCli.defaultPath);
      expect(
        await step.check(machine.contextFor(under)),
        isA<Ready>(),
        reason: 'an ordinary re-run corrects a machine that drifted, with nothing forced',
      );
    });

    test('a tool already at the pin is left alone', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers('command -v yq', '/usr/local/bin/yq\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n');

      const InstallYqCli step = InstallYqCli(version: 'v4.53.3', path: InstallYqCli.defaultPath);
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      expect(machine.changing, isEmpty);
    });

    test('a tool from the package manager skips on being there, taking no version', () async {
      final ClusterMachine machine = ClusterMachine()
        ..shell.answers('command -v jq', '/usr/bin/jq\n');
      const InstallJq step = InstallJq();
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
    });

    test('a pin nobody wrote is refused rather than resolved to whatever is current', () async {
      const InstallArgocdCli step = InstallArgocdCli(
        version: '',
        path: InstallArgocdCli.defaultPath,
      );
      final CheckResult answer = await step.check(ClusterMachine().contextFor(under));
      expect((answer as Blocked).reason, contains('pinned release'));
    });

    test('the fetch names the pinned release and never a latest one', () {
      const InstallArgocdCli argocd = InstallArgocdCli(
        version: 'v3.4.5',
        path: InstallArgocdCli.defaultPath,
      );
      expect(argocd.url, contains('/download/v3.4.5/'));
      expect(argocd.url, isNot(contains('latest')));

      const InstallVaultCli vault = InstallVaultCli(
        version: 'v2.0.3',
        directory: InstallVaultCli.defaultDirectory,
      );
      expect(vault.url, contains('/vault/2.0.3/vault_2.0.3_linux_amd64.zip'));

      const InstallYqCli yq = InstallYqCli(version: 'v4.53.3', path: InstallYqCli.defaultPath);
      expect(yq.url, contains('/download/v4.53.3/'));
    });

    test('the packed copy is removed whether the unpacking worked or not', () async {
      // A half-finished download left behind is what the next run would unpack.
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..fails('command -v vault')
        ..fails('unzip -o -d ${InstallVaultCli.defaultDirectory} ${InstallVaultCli.archive}');

      const InstallVaultCli step = InstallVaultCli(
        version: 'v2.0.3',
        directory: InstallVaultCli.defaultDirectory,
      );
      await expectLater(step.apply(machine.contextFor(under)), throwsA(isA<CommandFailed>()));
      expect(machine.files.deleted, contains(InstallVaultCli.archive));
    });
  });

  group('the pins held against the machine', () {
    const AssertCliToolVersions step = AssertCliToolVersions(
      tools: <String>[
        'argocd=v3.4.5',
        'vault=v2.0.3',
        'yq=v4.53.3',
        'jq=jq-1.8.2',
        'tailscale=v1.98.10',
      ],
      unpinnable: <String>['jq', 'tailscale'],
    );

    ClusterMachine withTools({Map<String, String> answers = const <String, String>{}}) {
      final ClusterMachine machine = ClusterMachine();
      for (final String tool in pinnedTools.keys) {
        machine.shell.answers('command -v $tool', '/usr/local/bin/$tool\n');
      }
      machine.shell
        ..answers('argocd version --client --short', 'argocd: v3.4.5+abcdef1\n')
        ..answers('vault version', 'Vault v2.0.3 (abcdef1), built 2026-01-01\n')
        ..answers('yq --version', 'yq (https://github.com/mikefarah/yq/) version v4.53.3\n')
        ..answers('jq --version', 'jq-1.8.2\n')
        ..answers('tailscale version', '1.98.10\n  tailscale commit: abcdef1\n');
      answers.forEach(machine.shell.answers);
      return machine;
    }

    test('the tag shapes come off before the comparison', () {
      expect(AssertCliToolVersions.bare('v4.53.3'), '4.53.3');
      expect(AssertCliToolVersions.bare('jq-1.8.2'), '1.8.2');
      expect(AssertCliToolVersions.bare('2.0.3'), '2.0.3');
    });

    test('a version reader answers with the bare version and nothing else', () async {
      // One of these prints the version and then the commit it was built from and more besides.
      final ClusterMachine machine = withTools();
      expect(
        await AssertCliToolVersions.installedVersion(machine.contextFor(under), 'tailscale'),
        '1.98.10',
      );
      expect(
        await AssertCliToolVersions.installedVersion(machine.contextFor(under), 'argocd'),
        '3.4.5',
      );
    });

    test('a machine at every pin passes', () async {
      expect(await step.check(withTools().contextFor(under)), isA<Satisfied>());
    });

    test('a tool that is missing fails, whether its version could be chosen or not', () async {
      final ClusterMachine machine = withTools();
      machine.shell
        ..fails('command -v jq')
        ..fails('command -v yq');

      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('jq is not on this machine'));
      expect(reason, contains('yq is not on this machine'));
    });

    test(
      'a version difference on a tool whose path takes no version is reported, not failed',
      () async {
        final ClusterMachine machine = withTools(
          answers: <String, String>{'jq --version': 'jq-1.7.1\n'},
        );
        expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
        expect(machine.said.join('\n'), contains('jq is at 1.7.1'));
        expect(machine.said.join('\n'), contains('no run can reach the pin'));
      },
    );

    test('a version difference on a tool fetched at a pin fails', () async {
      final ClusterMachine machine = withTools(
        answers: <String, String>{
          'yq --version': 'yq (https://github.com/mikefarah/yq/) version v4.40.0\n',
        },
      );
      final CheckResult answer = await step.check(machine.contextFor(under));
      expect((answer as Blocked).reason, contains('yq is at 4.40.0'));
    });

    test('a tool named here with nothing able to ask it its version is caught', () async {
      // The assertion is the only thing binding the list to the steps that install them: a tool
      // added to one and not the other would otherwise never be installed and nothing would say so.
      const AssertCliToolVersions unknown = AssertCliToolVersions(
        tools: <String>['helm=v4.2.3'],
        unpinnable: <String>[],
      );
      final CheckResult answer = await unknown.check(withTools().contextFor(under));
      expect((answer as Blocked).reason, contains('helm'));
    });

    test('everything wrong is reported at once', () async {
      final ClusterMachine machine = withTools();
      machine.shell
        ..fails('command -v argocd')
        ..fails('command -v vault');
      final CheckResult answer = await step.check(machine.contextFor(under));
      final String reason = (answer as Blocked).reason;
      expect(reason, contains('argocd'));
      expect(reason, contains('vault'));
    });
  });

  group('the shell aliases', () {
    const AddShellAlias step = AddShellAlias(
      alias: 'kubectl',
      command: 'microk8s.kubectl',
      rcFiles: <String>['.bashrc', '.zshrc'],
    );

    ClusterMachine account({Map<String, String> rcFiles = const <String, String>{}}) {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(
        'getent passwd $operatorUser',
        '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
      );
      rcFiles.forEach((String name, String content) {
        machine.files.contents['$operatorHome/$name'] = content;
      });
      return machine;
    }

    test('a startup file this machine does not have is never created', () async {
      final ClusterMachine machine = account();
      expect(await step.check(machine.contextFor(under)), isA<Satisfied>());
      await step.apply(machine.contextFor(under));
      expect(machine.files.written, isEmpty);
    });

    test('the alias goes into every startup file that is there', () async {
      final ClusterMachine machine = account(
        rcFiles: <String, String>{'.bashrc': '# a shell\n', '.zshrc': '# another shell\n'},
      );
      final StepContext context = machine.contextFor(under);

      expect(await step.check(context), isA<Ready>());
      await step.apply(context);
      expect(machine.files.contents['$operatorHome/.bashrc'], contains(step.line));
      expect(machine.files.contents['$operatorHome/.zshrc'], contains(step.line));
      expect(await step.check(context), isA<Satisfied>());
    });

    test('a second run adds no second line', () async {
      final ClusterMachine machine = account(
        rcFiles: <String, String>{'.bashrc': "alias kubectl='microk8s.kubectl'\n"},
      );
      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Satisfied>());
      expect(machine.files.written, isEmpty);
    });

    test('the home is read from the account rather than composed from the name', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell.answers(
        'getent passwd $operatorUser',
        '$operatorUser:x:1000:1000::/srv/$operatorUser:/bin/bash\n',
      );
      expect(
        await AddShellAlias.homeOf(machine.contextFor(under), operatorUser),
        '/srv/$operatorUser',
      );
    });
  });

  group('the credentials for this cluster', () {
    const ExportKubeconfig step = ExportKubeconfig();
    const String credentials = 'apiVersion: v1\nkind: Config\nclusters: []\n';

    test('the file is readable by its owner alone, and so is the directory', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('microk8s config', credentials);

      final StepContext context = machine.contextFor(under);
      expect(await step.check(context), isA<Ready>());
      await step.apply(context);

      expect(machine.files.contents['$operatorHome/.kube/config'], credentials);
      expect(machine.files.modes['$operatorHome/.kube/config'], 0x180);
      expect(machine.files.modes['$operatorHome/.kube'], 0x1c0);
      expect(await step.check(context), isA<Satisfied>());
    });

    test('the credentials never reach the plan', () async {
      final ClusterMachine machine = ClusterMachine();
      machine.shell
        ..answers(
          'getent passwd $operatorUser',
          '$operatorUser:x:1000:1000::$operatorHome:/bin/bash\n',
        )
        ..answers('microk8s config', 'apiVersion: v1\nusers:\n- name: admin\n  token: s3cr3t\n');

      final StepPlan plan = await step.plan(machine.contextFor(under));
      expect((plan as DiffPlan).after, isNot(contains('s3cr3t')));
    });

    test('it says what is lost, because the file is replaced whole', () {
      expect(step.irreversibleReason, contains('another cluster'));
    });
  });
}
